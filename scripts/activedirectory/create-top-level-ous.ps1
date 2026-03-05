# create-top-level-ous.ps1
# Reads a YAML config (like the sample you pasted), shows a change plan, asks for confirmation,
# then creates missing OUs (idempotent).
#
# UPDATE: Adds parameters to override dnsRoot, dn (domain DN), and parentDn.
# -DnsRoot and -DomainDN are informational/validation + used when rewriting DN suffixes.
# -ParentDN is the default parent for top-level OUs when the DN maps to a different domain.
#
# Usage examples:
#   .\create-ous-from-config.ps1 -ConfigPath .\config.yaml
#   .\create-ous-from-config.ps1 -ConfigPath .\config.yaml -DnsRoot cantrelloffice.cloud -DomainDN "DC=cantrelloffice,DC=cloud" -ParentDN "DC=cantrelloffice,DC=cloud"
#   .\create-ous-from-config.ps1 -ConfigPath .\config.yaml -DomainDN "DC=other,DC=lab" -ParentDN "DC=other,DC=lab" -WhatIf

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ConfigPath,

  # Override the DNS root from the YAML (optional, informational/validation)
  [Parameter(Mandatory = $false)]
  [string]$DnsRoot,

  # Override the domain DN from the YAML (optional).
  # This is the DN suffix we will map all OU DNs to when creating in a different domain.
  [Parameter(Mandatory = $false)]
  [string]$DomainDN,

  # Override the default parent DN for top-level OUs (optional).
  # Usually same as DomainDN; used as the -Path for New-ADOrganizationalUnit.
  [Parameter(Mandatory = $false)]
  [string]$ParentDN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-CurrentDomainDn { (Get-ADDomain).DistinguishedName }
function Get-CurrentDnsRoot { (Get-ADDomain).DNSRoot }

function Get-DnDepth {
  param([Parameter(Mandatory=$true)][string]$DistinguishedName)
  return ([regex]::Matches($DistinguishedName, '(?i)\bOU=')).Count
}

function Is-DomainDn {
  param([Parameter(Mandatory=$true)][string]$Dn)
  return (($Dn -match '(?i)\bDC=') -and -not ($Dn -match '(?i)\bOU='))
}

function Replace-DomainDn {
  param(
    [Parameter(Mandatory=$true)][string]$OuDn,
    [Parameter(Mandatory=$true)][string]$SourceDomainDn,
    [Parameter(Mandatory=$true)][string]$TargetDomainDn
  )

  if ([string]::IsNullOrWhiteSpace($OuDn)) { return $OuDn }
  if ([string]::IsNullOrWhiteSpace($SourceDomainDn)) { return $OuDn }
  if ([string]::IsNullOrWhiteSpace($TargetDomainDn)) { return $OuDn }

  # Replace trailing ",DC=...,DC=..." if it matches SourceDomainDn
  if ($OuDn -like "*,$SourceDomainDn") {
    return ($OuDn.Substring(0, $OuDn.Length - $SourceDomainDn.Length) + $TargetDomainDn)
  }

  return $OuDn
}

function Try-GetOu {
  param([Parameter(Mandatory=$true)][string]$Dn)
  try { Get-ADOrganizationalUnit -Identity $Dn -ErrorAction Stop } catch { $null }
}

function Get-ParentDnFromOuDn {
  param([Parameter(Mandatory=$true)][string]$OuDn)
  return ($OuDn -replace '^(?i)OU=[^,]+,', '')
}

function Get-NameFromOuDn {
  param([Parameter(Mandatory=$true)][string]$OuDn)
  if ($OuDn -match '^(?i)OU=([^,]+),') { return $Matches[1] }
  return $null
}

function Read-ConfigYaml {
  param([Parameter(Mandatory=$true)][string]$Path)

  if (-not (Test-Path -Path $Path)) { throw "Config file not found: $Path" }
  $raw = Get-Content -Path $Path -Raw

  # Preferred parser if available
  $cmd = Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue
  if ($cmd) { return ($raw | ConvertFrom-Yaml) }

  # Fallback parser (tailored for our config):
  # Extract sourceDomain.dnsRoot, sourceDomain.dn, and every (name/dn/parentDn/protected) block under trees/topLevelOUs.
  $lines = $raw -split "`r?`n"

  $sourceDnsRoot = $null
  $sourceDn = $null

  $inSourceDomain = $false
  foreach ($line in $lines) {
    $t = $line.Trim()

    if ($t -eq "sourceDomain:" -or $t -eq "sourceDomain :") { $inSourceDomain = $true; continue }
    if ($inSourceDomain -and $t -match '^(scope|topLevelOUs|trees|schemaVersion|exportedAtUtc)\b') { $inSourceDomain = $false }

    if ($inSourceDomain -and $t -match '^dnsRoot:\s*"([^"]+)"\s*$') { $sourceDnsRoot = $Matches[1]; continue }
    if ($inSourceDomain -and $t -match '^dn:\s*"([^"]+)"\s*$') { $sourceDn = $Matches[1]; continue }
  }

  # Collect OU records from all "dn:" occurrences
  $dns = New-Object System.Collections.Generic.List[string]
  $names = New-Object System.Collections.Generic.List[string]
  $parents = New-Object System.Collections.Generic.List[string]
  $protecteds = New-Object System.Collections.Generic.List[bool]

  $curName = $null
  $curDn = $null
  $curParent = $null
  $curProtected = $null

  foreach ($line in $lines) {
    $t = $line.Trim()

    if ($t -match '^name:\s*"([^"]+)"\s*$') { $curName = $Matches[1]; continue }
    if ($t -match '^dn:\s*"([^"]+)"\s*$') { $curDn = $Matches[1]; continue }
    if ($t -match '^parentDn:\s*"([^"]+)"\s*$') { $curParent = $Matches[1]; continue }
    if ($t -match '^protected:\s*(true|false)\s*$') { $curProtected = ($Matches[1].ToLower() -eq 'true'); continue }

    # When we have at least a DN, commit record (best-effort)
    if ($curDn -and ($t -eq "-" -or $t -eq "")) {
      $dns.Add($curDn) | Out-Null
      $names.Add($curName) | Out-Null
      $parents.Add($curParent) | Out-Null
      if ($null -eq $curProtected) { $protecteds.Add($true) | Out-Null } else { $protecteds.Add([bool]$curProtected) | Out-Null }

      $curName = $null; $curDn = $null; $curParent = $null; $curProtected = $null
    }
  }

  # Add last pending
  if ($curDn) {
    $dns.Add($curDn) | Out-Null
    $names.Add($curName) | Out-Null
    $parents.Add($curParent) | Out-Null
    if ($null -eq $curProtected) { $protecteds.Add($true) | Out-Null } else { $protecteds.Add([bool]$curProtected) | Out-Null }
  }

  # Build objects
  $ouRecords = @()
  for ($i = 0; $i -lt $dns.Count; $i++) {
    $ouRecords += [pscustomobject]@{
      name      = $names[$i]
      dn        = $dns[$i]
      parentDn  = $parents[$i]
      protected = $protecteds[$i]
    }
  }

  return [pscustomobject]@{
    sourceDomain = [pscustomobject]@{
      dnsRoot = $sourceDnsRoot
      dn      = $sourceDn
    }
    __records = $ouRecords
  }
}

# ---------------- Main ----------------

Import-Module ActiveDirectory -ErrorAction Stop

$config = Read-ConfigYaml -Path $ConfigPath

# Resolve source values (from YAML unless overridden)
$sourceDnsRoot = $null
$sourceDomainDn = $null
$records = @()

if ($config.PSObject.Properties.Name -contains "__records") {
  # fallback parsed
  $sourceDnsRoot = [string]$config.sourceDomain.dnsRoot
  $sourceDomainDn = [string]$config.sourceDomain.dn
  $records = @($config.__records)
} else {
  # ConvertFrom-Yaml parsed (full structure)
  $sourceDnsRoot = [string]$config.sourceDomain.dnsRoot
  $sourceDomainDn = [string]$config.sourceDomain.dn

  $tmp = New-Object System.Collections.Generic.List[object]

  # Prefer trees.ous + trees.root
  foreach ($t in @($config.trees)) {
    if ($t.root -and $t.root.dn) {
      $tmp.Add([pscustomobject]@{
        name      = [string]$t.root.name
        dn        = [string]$t.root.dn
        parentDn  = [string]$t.root.parentDn
        protected = [bool]$t.root.protected
      }) | Out-Null
    }
    foreach ($ou in @($t.ous)) {
      if ($ou.dn) {
        $tmp.Add([pscustomobject]@{
          name      = [string]$ou.name
          dn        = [string]$ou.dn
          parentDn  = $null
          protected = [bool]$ou.protected
        }) | Out-Null
      }
    }
  }

  # If no trees, fall back to topLevelOUs
  if ($tmp.Count -eq 0 -and $config.topLevelOUs) {
    foreach ($ou in @($config.topLevelOUs)) {
      $tmp.Add([pscustomobject]@{
        name      = [string]$ou.name
        dn        = [string]$ou.dn
        parentDn  = [string]$ou.parentDn
        protected = [bool]$ou.protected
      }) | Out-Null
    }
  }

  $records = @($tmp)
}

# Apply overrides
if ($DnsRoot) { $sourceDnsRoot = $DnsRoot }
if ($DomainDN) { $targetDomainDn = $DomainDN } else { $targetDomainDn = Get-CurrentDomainDn }
if ($ParentDN) { $defaultParentDn = $ParentDN } else { $defaultParentDn = $targetDomainDn }

if (-not $sourceDomainDn) {
  throw "Could not determine sourceDomain.dn from config. Ensure YAML includes sourceDomain.dn"
}

# Optional sanity check: warn if your override doesn't match current AD domain
$currentDn = Get-CurrentDomainDn
$currentDns = Get-CurrentDnsRoot
if ($targetDomainDn -ne $currentDn) {
  Write-Warning ("Target DomainDN '{0}' does not match current AD domain DN '{1}'. Ensure you are connected to the right domain/controller." -f $targetDomainDn, $currentDn)
}
if ($sourceDnsRoot -and ($sourceDnsRoot -ne $currentDns) -and (-not $DnsRoot)) {
  # Not blocking, just FYI
  Write-Verbose ("Config dnsRoot differs from current domain DNSRoot. Config: {0} Current: {1}" -f $sourceDnsRoot, $currentDns)
}

# Normalize records: map dn/parentDn to target domain DN; derive name/parentDn if missing
$normalized = foreach ($r in $records) {
  if (-not $r -or -not $r.dn) { continue }

  $dn = Replace-DomainDn -OuDn ([string]$r.dn) -SourceDomainDn $sourceDomainDn -TargetDomainDn $targetDomainDn
  if (Is-DomainDn $dn) { continue } # never try to create domain root

  $name = if ($r.name) { [string]$r.name } else { Get-NameFromOuDn -OuDn $dn }
  if ([string]::IsNullOrWhiteSpace($name)) { continue }

  $parent = $null
  if ($r.parentDn) {
    $parent = Replace-DomainDn -OuDn ([string]$r.parentDn) -SourceDomainDn $sourceDomainDn -TargetDomainDn $targetDomainDn
  } else {
    $parent = Get-ParentDnFromOuDn -OuDn $dn
  }

  # If the computed parent is the SOURCE domain DN, map to target default parent
  if ($parent -eq $sourceDomainDn) { $parent = $defaultParentDn }
  # If parent is a domain DN, that's OK (New-ADOrganizationalUnit -Path can take domain DN)
  if ([string]::IsNullOrWhiteSpace($parent)) { $parent = $defaultParentDn }

  $prot = $true
  if ($null -ne $r.protected) { $prot = [bool]$r.protected }

  [pscustomobject]@{
    name      = $name
    dn        = $dn
    parentDn  = $parent
    protected = $prot
    depth     = Get-DnDepth -DistinguishedName $dn
  }
}

# Unique by DN, keep first occurrence
$normalized = $normalized | Group-Object dn | ForEach-Object { $_.Group[0] }

# Sort: shallow to deep so parents are created first
$ordered = $normalized | Sort-Object depth, dn

# Build plan
$plan = foreach ($item in $ordered) {
  $exists = Try-GetOu -Dn $item.dn
  [pscustomobject]@{
    Action    = if ($exists) { "SKIP" } else { "CREATE" }
    Name      = $item.name
    ParentDN  = $item.parentDn
    DN        = $item.dn
    Protected = $item.protected
  }
}

$toCreate = @($plan | Where-Object { $_.Action -eq "CREATE" })
$toSkip   = @($plan | Where-Object { $_.Action -eq "SKIP" })

Write-Host ""
Write-Host "============================================="
Write-Host " OU Create Plan (from YAML config)"
Write-Host "============================================="
Write-Host ("Config        : {0}" -f $ConfigPath)
Write-Host ("dnsRoot       : {0}" -f ($sourceDnsRoot ? $sourceDnsRoot : "<not set>"))
Write-Host ("sourceDomainDN: {0}" -f $sourceDomainDn)
Write-Host ("targetDomainDN: {0}" -f $targetDomainDn)
Write-Host ("defaultParent : {0}" -f $defaultParentDn)
Write-Host ("Total OUs     : {0}" -f $plan.Count)
Write-Host ("To create     : {0}" -f $toCreate.Count)
Write-Host ("Already exist : {0}" -f $toSkip.Count)
Write-Host ""

if ($plan.Count -gt 0) {
  $plan | Select-Object Action, Name, Protected, ParentDN, DN | Format-Table -AutoSize
}

if ($toCreate.Count -eq 0) {
  Write-Host ""
  Write-Host "No changes required. All OUs already exist."
  exit 0
}

Write-Host ""
$confirm = Read-Host "Proceed to create $($toCreate.Count) OU(s)? Type YES to continue"
if ($confirm -ne "YES") {
  Write-Host "Aborted. No changes were made."
  exit 0
}

Write-Host ""
Write-Host "============================================="
Write-Host " Creating OUs"
Write-Host "============================================="
Write-Host ""

$created = 0
$failed  = 0
$skipped = 0

foreach ($item in $ordered) {
  $exists = Try-GetOu -Dn $item.dn
  if ($exists) { $skipped++; continue }

  try {
    if ($PSCmdlet.ShouldProcess($item.dn, "Create OU")) {
      New-ADOrganizationalUnit -Name $item.name -Path $item.parentDn -ProtectedFromAccidentalDeletion $item.protected -ErrorAction Stop
      Write-Host ("CREATE: {0}" -f $item.dn)
      $created++
    }
  }
  catch {
    Write-Warning ("FAIL: {0} :: {1}" -f $item.dn, $_.Exception.Message)
    $failed++
  }
}

Write-Host ""
Write-Host "============================================="
Write-Host " Summary"
Write-Host "============================================="
Write-Host ("Created : {0}" -f $created)
Write-Host ("Skipped : {0}" -f $skipped)
Write-Host ("Failed  : {0}" -f $failed)
Write-Host ""
