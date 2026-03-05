# get-top-level-ous.ps1
# Discovers top-level OUs (direct children of the domain root) whose Name begins with "_"
# Displays:
#   - top-level underscore OUs
#   - each top-level underscore OU + ALL descendant OUs beneath it (subtree) as an exec-friendly tree
# Saves:
#   - YAML config file for downstream automation (uses ConvertTo-Yaml if available, otherwise a dependency-free fallback)
#
# Fixes included:
# - StrictMode-safe array handling (no .Count-on-string surprises)
# - Tree builder uses parent-DN relationships (reliable)
# - Nested function no longer trips over "if" parsing (no inline if in argument position)

[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string]$OutDir = (Join-Path $PSScriptRoot "outputs"),

  [Parameter(Mandatory = $false)]
  [string]$OutFileName = "underscore-ous.config.yaml",

  [Parameter(Mandatory = $false)]
  [switch]$AsciiTree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

function ConvertTo-SimpleYaml {
  param([Parameter(Mandatory = $true)]$Object, [int]$Indent = 0)

  $pad = (' ' * $Indent)
  $lines = New-Object System.Collections.Generic.List[string]

  if ($null -eq $Object) { $lines.Add(('{0}null' -f $pad)); return $lines }
  if ($Object -is [hashtable]) { $Object = [pscustomobject]$Object }

  $hasProps = ($Object -is [psobject]) -and $Object.PSObject -and $Object.PSObject.Properties -and ((@($Object.PSObject.Properties).Length) -gt 0)

  if (($Object -is [System.Collections.IEnumerable]) -and -not ($Object -is [string]) -and -not $hasProps) {
    foreach ($item in @($Object)) {
      if ($item -is [string]) { $lines.Add(('{0}- "{1}"' -f $pad, $item.Replace('"','\"'))) }
      elseif ($item -is [bool]) { $lines.Add(('{0}- {1}' -f $pad, $item.ToString().ToLower())) }
      elseif ($item -is [int] -or $item -is [long] -or $item -is [double] -or $item -is [decimal]) { $lines.Add(('{0}- {1}' -f $pad, $item)) }
      else {
        $itemHasProps = ($item -is [psobject]) -and $item.PSObject -and $item.PSObject.Properties -and ((@($item.PSObject.Properties).Length) -gt 0)
        if ($itemHasProps -or ($item -is [hashtable])) {
          $lines.Add(('{0}-' -f $pad))
          (ConvertTo-SimpleYaml -Object $item -Indent ($Indent + 2)) | ForEach-Object { $lines.Add($_) }
        } else {
          $lines.Add(('{0}- {1}' -f $pad, $item))
        }
      }
    }
    return $lines
  }

  if ($hasProps) {
    foreach ($p in @($Object.PSObject.Properties)) {
      $key = [string]$p.Name
      $val = $p.Value

      if ($null -eq $val) { $lines.Add(('{0}{1}: null' -f $pad, $key)); continue }
      if ($val -is [string]) { $lines.Add(('{0}{1}: "{2}"' -f $pad, $key, $val.Replace('"','\"'))); continue }
      if ($val -is [bool]) { $lines.Add(('{0}{1}: {2}' -f $pad, $key, $val.ToString().ToLower())); continue }
      if ($val -is [int] -or $val -is [long] -or $val -is [double] -or $val -is [decimal]) { $lines.Add(('{0}{1}: {2}' -f $pad, $key, $val)); continue }

      if (($val -is [System.Collections.IEnumerable]) -and -not ($val -is [string])) {
        $lines.Add(('{0}{1}:' -f $pad, $key))
        foreach ($item in @($val)) {
          $itemHasProps = ($item -is [psobject]) -and $item.PSObject -and $item.PSObject.Properties -and ((@($item.PSObject.Properties).Length) -gt 0)
          if ($itemHasProps -or ($item -is [hashtable])) {
            $lines.Add(('{0}  -' -f $pad))
            (ConvertTo-SimpleYaml -Object $item -Indent ($Indent + 4)) | ForEach-Object { $lines.Add($_) }
          } elseif ($item -is [string]) {
            $lines.Add(('{0}  - "{1}"' -f $pad, $item.Replace('"','\"')))
          } elseif ($item -is [bool]) {
            $lines.Add(('{0}  - {1}' -f $pad, $item.ToString().ToLower()))
          } else {
            $lines.Add(('{0}  - {1}' -f $pad, $item))
          }
        }
        continue
      }

      $lines.Add(('{0}{1}:' -f $pad, $key))
      (ConvertTo-SimpleYaml -Object $val -Indent ($Indent + 2)) | ForEach-Object { $lines.Add($_) }
    }
    return $lines
  }

  if ($Object -is [string]) { $lines.Add(('{0}"{1}"' -f $pad, $Object.Replace('"','\"'))) }
  else { $lines.Add(('{0}{1}' -f $pad, $Object)) }

  return $lines
}

function Get-TreeGlyphs {
  param([switch]$ForceAscii)

  if ($ForceAscii) {
    return @{
      Tee    = "|- "
      Elbow  = "+- "
      Pipe   = "|  "
      Space  = "   "
    }
  }

  return @{
    Tee    = ([char]0x251C + [char]0x2500 + ' ')  # ├─
    Elbow  = ([char]0x2514 + [char]0x2500 + ' ')  # └─
    Pipe   = ([char]0x2502 + '  ')                # │
    Space  = "   "
  }
}

function Get-ParentOuDn {
  param([Parameter(Mandatory=$true)][string]$OuDn)
  return ($OuDn -replace '^(?i)OU=[^,]+,', '')
}

function Write-OuTreeByParent {
  param(
    [Parameter(Mandatory=$true)][string]$RootDn,
    [Parameter(Mandatory=$true)]$Ous,
    [Parameter(Mandatory=$true)]$Glyphs
  )

  $ousArr = @($Ous)

  # Index nodes by DN
  $nodes = @{}
  foreach ($ou in $ousArr) {
    $dn = [string]$ou.DistinguishedName
    $nodes[$dn] = [pscustomobject]@{
      Name     = [string]$ou.Name
      DN       = $dn
      Children = New-Object System.Collections.Generic.List[string]
    }
  }

  # Build parent->children links (only within subtree)
  foreach ($dn in @($nodes.Keys)) {
    if ($dn -ieq $RootDn) { continue }
    $parentDn = Get-ParentOuDn -OuDn $dn
    if ($nodes.ContainsKey($parentDn)) {
      $null = $nodes[$parentDn].Children.Add($dn)
    }
  }

  function Write-Node {
    param(
      [Parameter(Mandatory=$true)][string]$NodeDn,
      [string]$Prefix = "",
      [bool]$IsLast = $true,
      [bool]$IsRoot = $false
    )

    $node = $nodes[$NodeDn]

    if ($IsRoot) {
      Write-Host $node.Name
    } else {
      $branch = $Glyphs.Tee
      if ($IsLast) { $branch = $Glyphs.Elbow }
      Write-Host ("{0}{1}{2}" -f $Prefix, $branch, $node.Name)
    }

    $kids = @($node.Children | Sort-Object)
    for ($i = 0; $i -lt $kids.Count; $i++) {
      $kidDn = $kids[$i]
      $kidIsLast = ($i -eq ($kids.Count - 1))

      $nextPrefix = ""
      if (-not $IsRoot) {
        if ($IsLast) { $nextPrefix = $Prefix + $Glyphs.Space }
        else { $nextPrefix = $Prefix + $Glyphs.Pipe }
      } else {
        $nextPrefix = ""
      }

      Write-Node -NodeDn $kidDn -Prefix $nextPrefix -IsLast $kidIsLast -IsRoot:$false
    }
  }

  Write-Node -NodeDn $RootDn -IsRoot:$true
}

Import-Module ActiveDirectory -ErrorAction Stop

$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName
$domainDnsName = $domain.DNSRoot

$topLevel = @(
  Get-ADOrganizationalUnit -Filter 'Name -like "_*"' `
    -SearchBase $domainDn `
    -SearchScope OneLevel `
    -Properties Name, DistinguishedName, ProtectedFromAccidentalDeletion |
    Sort-Object Name
)

Write-Host ""
Write-Host "============================================="
Write-Host " Top-Level OUs Starting With '_'"
Write-Host " Domain: $domainDnsName"
Write-Host " DN    : $domainDn"
Write-Host " Count : $($topLevel.Count)"
Write-Host "============================================="
Write-Host ""

$topLevel |
  Select-Object `
    @{n="OU Name"; e={$_.Name}}, `
    @{n="Protected"; e={$_.ProtectedFromAccidentalDeletion}}, `
    @{n="DistinguishedName"; e={$_.DistinguishedName}} |
  Format-Table -AutoSize

Write-Host ""
Write-Host "OU Names (quick list):"
$topLevel | Select-Object -ExpandProperty Name | ForEach-Object { "  - $_" }
Write-Host ""

Write-Host "============================================="
Write-Host " OU Trees (exec-friendly)"
Write-Host "============================================="
Write-Host ""

$glyphs = Get-TreeGlyphs -ForceAscii:$AsciiTree
$trees = @()

foreach ($root in $topLevel) {
  $rootDn = [string]$root.DistinguishedName
  $rootName = [string]$root.Name

  $subtree = @(
    Get-ADOrganizationalUnit -Filter * `
      -SearchBase $rootDn `
      -SearchScope Subtree `
      -Properties Name, DistinguishedName, ProtectedFromAccidentalDeletion |
      Sort-Object DistinguishedName
  )

  Write-Host ""
  Write-Host "---------------------------------------------"
  Write-Host ""
  Write-Host ("[{0}] {1}" -f $rootName, $rootDn)
  Write-Host ("  Total OUs in subtree: {0}" -f $subtree.Count)
  Write-Host ""

  # Print ALL OUs under the root
  Write-OuTreeByParent -RootDn $rootDn -Ous $subtree -Glyphs $glyphs

  $trees += [pscustomobject]@{
    root = [pscustomobject]@{
      name      = $rootName
      dn        = $rootDn
      protected = [bool]$root.ProtectedFromAccidentalDeletion
      parentDn  = $domainDn
    }
    ous = $subtree | ForEach-Object {
      [pscustomobject]@{
        name      = $_.Name
        dn        = $_.DistinguishedName
        protected = [bool]$_.ProtectedFromAccidentalDeletion
      }
    }
  }
}

Write-Host ""
Write-Host "============================================="
Write-Host " Export"
Write-Host "============================================="
Write-Host ""

$config = [pscustomobject]@{
  schemaVersion  = "1.6"
  exportedAtUtc  = (Get-Date).ToUniversalTime().ToString("o")
  sourceDomain   = [pscustomobject]@{
    dnsRoot = $domainDnsName
    dn      = $domainDn
  }
  scope = [pscustomobject]@{
    type                = "TopLevelUnderscorePlusSubtree"
    searchBase          = $domainDn
    topLevelSearchScope = "OneLevel"
    topLevelNameFilter  = "Name -like '_*'"
    subtreeSearchScope  = "Subtree"
  }
  topLevelOUs = $topLevel | ForEach-Object {
    [pscustomobject]@{
      name      = $_.Name
      dn        = $_.DistinguishedName
      parentDn  = $domainDn
      protected = [bool]$_.ProtectedFromAccidentalDeletion
    }
  }
  trees = $trees
}

New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
$configPath = Join-Path $OutDir $OutFileName

$yamlText = $null
if (Get-Command ConvertTo-Yaml -ErrorAction SilentlyContinue) {
  $yamlText = $config | ConvertTo-Yaml
} else {
  $yamlText = (ConvertTo-SimpleYaml -Object $config -Indent 0) -join "`r`n"
}

$yamlText | Set-Content -Path $configPath -Encoding UTF8

Write-Host "Saved YAML config file:"
Write-Host ("  {0}" -f $configPath)
Write-Host ""
