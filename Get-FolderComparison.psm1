using namespace System.Security.Cryptography
using namespace System.IO

<#
.SYNOPSIS
    Compares two folders and reports file changes, moves, renames, and updates.

.DESCRIPTION
    This module compares two directories (Source and Destination) and:
    1. Identifies files with the same relative path and checks if updated or unchanged.
    2. Uses MD5 checksums to detect files that were moved, renamed, or both.
    3. Finds files with similar names in the same relative path to suggest likely renames/updates.
    4. Reports files as added or removed if unmatched.

.EXAMPLE
    Import-Module ./Get-FolderComparison.ps1
    Get-FolderComparison -SourcePath "C:\Source" -DestinationPath "C:\Dest"
#>

function Get-FolderComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    # Validate paths exist
    if (-not (Test-Path $SourcePath -PathType Container)) {
        throw "Source path does not exist or is not a directory: $SourcePath"
    }
    if (-not (Test-Path $DestinationPath -PathType Container)) {
        throw "Destination path does not exist or is not a directory: $DestinationPath"
    }

    function Get-FileList($Root, $Label = "Scanning") {
        Write-Host "Scanning directory: $Root" -ForegroundColor Cyan
        $files = @()
        $count = 0
        
        Get-ChildItem -Path $Root -Recurse -File | ForEach-Object {
            $count++
            if ($count % 100 -eq 0) {
                Write-Progress -Activity "$Label files" -Status "Found $count files so far..." -PercentComplete -1
            }
            
            $files += [PSCustomObject]@{
                FullPath      = $_.FullName
                RelativePath  = $_.FullName.Substring($Root.Length).TrimStart('\','/')
                Name          = $_.Name
                Length        = $_.Length
                LastWriteTime = $_.LastWriteTimeUtc
                MD5           = $null
            }
        }
        
        Write-Progress -Activity "$Label files" -Completed
        Write-Host "Found $count files in $Label directory" -ForegroundColor Green
        return $files
    }

    function Get-MD5($Path) {
        $md5 = [MD5]::Create()
        $stream = [File]::OpenRead($Path)
        try {
            $hash = $md5.ComputeHash($stream)
            return ([BitConverter]::ToString($hash) -replace '-', '').ToLower()
        } finally {
            $stream.Dispose()
            $md5.Dispose()
        }
    }
    
    function Show-Progress($Current, $Total, $Activity) {
        if ($Total -gt 0) {
            $percent = [math]::Round(($Current / $Total) * 100, 1)
            Write-Progress -Activity $Activity -Status "$Current of $Total files processed ($percent%)" -PercentComplete $percent
        }
    }

    $srcFiles = Get-FileList $SourcePath "Source"
    $dstFiles = Get-FileList $DestinationPath "Destination"
    
    $totalFiles = $srcFiles.Count + $dstFiles.Count
    Write-Host "Total: $($srcFiles.Count) source files and $($dstFiles.Count) destination files ($totalFiles total)" -ForegroundColor Cyan

    # Index by relative path
    $srcByRel = @{}
    foreach ($f in $srcFiles) { $srcByRel[$f.RelativePath] = $f }
    $dstByRel = @{}
    foreach ($f in $dstFiles) { $dstByRel[$f.RelativePath] = $f }

    # 1. Compare by relative path
    $results = @()
    $matchedSrc = @{}
    $matchedDst = @{}
    $md5ProcessedCount = 0

    foreach ($rel in $srcByRel.Keys) {
        if ($dstByRel.ContainsKey($rel)) {
            $src = $srcByRel[$rel]
            $dst = $dstByRel[$rel]
            if ($src.Length -eq $dst.Length -and $src.LastWriteTime -eq $dst.LastWriteTime) {
                $status = "Unchanged"
            } else {
                if (-not $src.MD5) { 
                    $src.MD5 = Get-MD5 $src.FullPath 
                    $md5ProcessedCount++
                    if ($md5ProcessedCount % 10 -eq 0 -and $totalFiles -gt 50) {
                        Show-Progress $md5ProcessedCount $totalFiles "Comparing files (MD5 calculation)"
                    }
                }
                if (-not $dst.MD5) { 
                    $dst.MD5 = Get-MD5 $dst.FullPath 
                    $md5ProcessedCount++
                    if ($md5ProcessedCount % 10 -eq 0 -and $totalFiles -gt 50) {
                        Show-Progress $md5ProcessedCount $totalFiles "Comparing files (MD5 calculation)"
                    }
                }
                if ($src.MD5 -eq $dst.MD5) {
                    $status = "Unchanged"
                } else {
                    $status = "Updated"
                }
            }
            $results += [PSCustomObject]@{
                Type         = $status
                SourcePath   = $src.FullPath
                DestinationPath = $dst.FullPath
                RelativePath = $rel
                Index        = $null
                DuplicateOf  = $null
            }
            $matchedSrc[$rel] = $true
            $matchedDst[$rel] = $true
        }
    }

    # 2. Find moved/renamed files by MD5
    $srcUnmatched = $srcFiles | Where-Object { -not $matchedSrc.ContainsKey($_.RelativePath) }
    $dstUnmatched = $dstFiles | Where-Object { -not $matchedDst.ContainsKey($_.RelativePath) }

    # Build MD5 index for unmatched files with progress tracking
    $totalUnmatched = $srcUnmatched.Count + $dstUnmatched.Count
    $processed = 0
    
    if ($totalUnmatched -gt 0) {
        Write-Host "Calculating MD5 checksums for $totalUnmatched unmatched files..." -ForegroundColor Yellow
    }
    
    foreach ($f in $srcUnmatched) { 
        if (-not $f.MD5) { 
            $f.MD5 = Get-MD5 $f.FullPath 
            $processed++
            if ($totalUnmatched -gt 10) { Show-Progress $processed $totalUnmatched "Computing MD5 checksums" }
        }
    }
    foreach ($f in $dstUnmatched) { 
        if (-not $f.MD5) { 
            $f.MD5 = Get-MD5 $f.FullPath 
            $processed++
            if ($totalUnmatched -gt 10) { Show-Progress $processed $totalUnmatched "Computing MD5 checksums" }
        }
    }
    
    if ($totalUnmatched -gt 10) { Write-Progress -Activity "Computing MD5 checksums" -Completed }
    $srcByMD5 = @{}
    foreach ($f in $srcUnmatched) { $srcByMD5[$f.MD5] = $f }
    $dstByMD5 = @{}
    foreach ($f in $dstUnmatched) { $dstByMD5[$f.MD5] = $f }

    foreach ($md5 in $srcByMD5.Keys) {
        if ($dstByMD5.ContainsKey($md5)) {
            $src = $srcByMD5[$md5]
            $dst = $dstByMD5[$md5]
            $srcDir = [System.IO.Path]::GetDirectoryName($src.RelativePath)
            $dstDir = [System.IO.Path]::GetDirectoryName($dst.RelativePath)
            $moveType = if ($src.Name -eq $dst.Name) {
                "Moved"
            } elseif ($srcDir -eq $dstDir) {
                "Renamed"
            } else {
                "MovedAndRenamed"
            }
            $results += [PSCustomObject]@{
                Type         = $moveType
                SourcePath   = $src.FullPath
                DestinationPath = $dst.FullPath
                RelativePath = "$($src.RelativePath) -> $($dst.RelativePath)"
                Index        = $null
                DuplicateOf  = $null
            }
            $matchedSrc[$src.RelativePath] = $true
            $matchedDst[$dst.RelativePath] = $true
        }
    }

    # 3. Similar names in same relative folder
    $srcUnmatched = $srcFiles | Where-Object { -not $matchedSrc.ContainsKey($_.RelativePath) }
    $dstUnmatched = $dstFiles | Where-Object { -not $matchedDst.ContainsKey($_.RelativePath) }
    foreach ($src in $srcUnmatched) {
        $srcDir = Split-Path $src.RelativePath
        $candidates = $dstUnmatched | Where-Object { (Split-Path $_.RelativePath) -eq $srcDir }
        foreach ($dst in $candidates) {
            # Use Levenshtein distance for similarity
            $dist = [Microsoft.PowerShell.Utility.StringSimilarity]::LevenshteinDistance($src.Name, $dst.Name)
            if ($dist -le 3) {
                $results += [PSCustomObject]@{
                    Type         = "LikelyRenamedOrUpdated"
                    SourcePath   = $src.FullPath
                    DestinationPath = $dst.FullPath
                    RelativePath = "$($src.RelativePath) -> $($dst.RelativePath)"
                    Index        = $null
                    DuplicateOf  = $null
                }
                $matchedSrc[$src.RelativePath] = $true
                $matchedDst[$dst.RelativePath] = $true
                break
            }
        }
    }

    # 4. Remaining: Added/Removed
    $srcUnmatched = $srcFiles | Where-Object { -not $matchedSrc.ContainsKey($_.RelativePath) }
    foreach ($src in $srcUnmatched) {
        $results += [PSCustomObject]@{
            Type         = "Removed"
            SourcePath   = $src.FullPath
            DestinationPath = $null
            RelativePath = $src.RelativePath
            Index        = $null
            DuplicateOf  = $null
        }
    }
    $dstUnmatched = $dstFiles | Where-Object { -not $matchedDst.ContainsKey($_.RelativePath) }
    foreach ($dst in $dstUnmatched) {
        $results += [PSCustomObject]@{
            Type         = "Added"
            SourcePath   = $null
            DestinationPath = $dst.FullPath
            RelativePath = $dst.RelativePath
            Index        = $null
            DuplicateOf  = $null
        }
    }

    # 5. Post-process: Add indices and detect duplicates (1-based indexing)
    for ($i = 0; $i -lt $results.Count; $i++) {
        $results[$i].Index = $i + 1
    }

    # Build MD5 lookup for all destination files for duplicate detection
    $allDstByMD5 = @{}
    foreach ($f in $dstFiles) {
        if (-not $f.MD5) { $f.MD5 = Get-MD5 $f.FullPath }
        if (-not $allDstByMD5.ContainsKey($f.MD5)) {
            $allDstByMD5[$f.MD5] = @()
        }
        $allDstByMD5[$f.MD5] += $f
    }

    # Check removed files for duplicates in destination
    $removedResults = $results | Where-Object Type -eq "Removed"
    foreach ($removedResult in $removedResults) {
        $srcFile = $srcFiles | Where-Object FullPath -eq $removedResult.SourcePath
        if ($srcFile -and $srcFile.MD5 -and $allDstByMD5.ContainsKey($srcFile.MD5)) {
            $duplicates = $allDstByMD5[$srcFile.MD5]
            if ($duplicates.Count -gt 0) {
                # Find the result index for the first duplicate
                $duplicateResult = $results | Where-Object { $_.DestinationPath -eq $duplicates[0].FullPath }
                if ($duplicateResult) {
                    $removedResult.Type = "RemovedDuplicate"
                    $removedResult.DestinationPath = $duplicates[0].FullPath
                    $removedResult.DuplicateOf = $duplicateResult.Index
                }
            }
        }
    }

    # Mark duplicates within destination files
    $destResults = $results | Where-Object { $null -ne $_.DestinationPath }
    $processedMD5 = @{}
    
    foreach ($result in $destResults) {
        $dstFile = $dstFiles | Where-Object FullPath -eq $result.DestinationPath
        if ($dstFile -and $dstFile.MD5) {
            if ($processedMD5.ContainsKey($dstFile.MD5)) {
                # This is a duplicate
                $originalIndex = $processedMD5[$dstFile.MD5]
                $result.DuplicateOf = $originalIndex
            } else {
                # First occurrence of this MD5
                $processedMD5[$dstFile.MD5] = $result.Index
            }
        }
    }

    return $results
}

Export-ModuleMember -Function Get-FolderComparison

# Helper for Levenshtein distance (PowerShell 7+ has this, otherwise use a custom implementation)
if (-not ("Microsoft.PowerShell.Utility.StringSimilarity" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
namespace Microsoft.PowerShell.Utility {
    public static class StringSimilarity {
        public static int LevenshteinDistance(string s, string t) {
            if (String.IsNullOrEmpty(s)) return String.IsNullOrEmpty(t) ? 0 : t.Length;
            if (String.IsNullOrEmpty(t)) return s.Length;
            int[,] d = new int[s.Length + 1, t.Length + 1];
            for (int i = 0; i <= s.Length; i++) d[i, 0] = i;
            for (int j = 0; j <= t.Length; j++) d[0, j] = j;
            for (int i = 1; i <= s.Length; i++) {
                for (int j = 1; j <= t.Length; j++) {
                    int cost = (t[j - 1] == s[i - 1]) ? 0 : 1;
                    d[i, j] = Math.Min(
                        Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1),
                        d[i - 1, j - 1] + cost
                    );
                }
            }
            return d[s.Length, t.Length];
        }
    }
}
"@
}