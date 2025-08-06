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
        $skipped = 0
        
        Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                # Test if file is accessible before adding to list
                if ([System.IO.File]::Exists($_.FullName)) {
                    $count++
                    if ($count % 100 -eq 0) {
                        $statusMsg = "Found $count files"
                        if ($skipped -gt 0) { $statusMsg += " (skipped $skipped inaccessible)" }
                        Write-Progress -Activity "$Label files" -Status "$statusMsg..." -PercentComplete -1
                    }
                    
                    $files += [PSCustomObject]@{
                        FullPath      = $_.FullName
                        RelativePath  = $_.FullName.Substring($Root.Length).TrimStart('\','/')
                        Name          = $_.Name
                        Length        = $_.Length
                        LastWriteTime = $_.LastWriteTimeUtc
                        MD5           = $null
                    }
                } else {
                    $skipped++
                    # Enhanced debugging for failed file existence check
                    Write-Warning "File existence check failed for: $($_.FullName)"
                    Write-Warning "  └─ File appears in directory listing but [System.IO.File]::Exists() returned false"
                    Write-Warning "  └─ Path length: $($_.FullName.Length) characters"
                    if ($_.FullName -like "*Egnyte*" -or $_.FullName -like "*OneDrive*" -or $_.FullName -like "*Dropbox*") {
                        Write-Warning "  └─ Cloud storage file detected - may not be synced locally or accessible"
                    }
                    if ($_.FullName.Length -gt 260) {
                        Write-Warning "  └─ Path exceeds 260 character limit - this may cause access issues"
                    }
                }
            } catch {
                $skipped++
                $errorType = $_.Exception.GetType().Name
                Write-Warning "Exception processing file: $($_.FullName)"
                Write-Warning "  └─ Error Type: $errorType"
                Write-Warning "  └─ Error Message: $($_.Exception.Message)"
                Write-Warning "  └─ Path length: $($_.FullName.Length) characters"
                
                # Check for cloud service specific errors
                if ($errorType -eq "IOException" -or 
                    $errorType -eq "UnauthorizedAccessException" -or
                    $errorType -eq "DirectoryServiceException" -or
                    $_.Exception.Message -like "*network*" -or 
                    $_.Exception.Message -like "*timeout*" -or
                    $_.Exception.Message -like "*rate*" -or
                    $_.Exception.Message -like "*egnyte*" -or
                    $_.Exception.Message -like "*cloud*" -or
                    $_.Exception.Message -like "*access denied*" -or
                    $_.Exception.Message -like "*sharing violation*") {
                    Write-Warning "  └─ This appears to be a cloud service or network related error"
                    Write-Warning "  └─ Consider checking network connectivity or Egnyte sync status"
                }
                
                # Check for long path issues
                if ($_.FullName.Length -gt 260) {
                    Write-Warning "  └─ Long path detected - this may be the cause of the error"
                }
                
                # Check for special characters
                if ($_.FullName -match '[^\x00-\x7F]' -or $_.FullName -match '[\[\]{}()]') {
                    Write-Warning "  └─ Special characters or Unicode detected in path - this may cause issues"
                }
            }
        }
        
        Write-Progress -Activity "$Label files" -Completed
        $resultMsg = "Found $count files in $Label directory"
        if ($skipped -gt 0) { $resultMsg += " (skipped $skipped inaccessible files)" }
        Write-Host $resultMsg -ForegroundColor Green
        return $files
    }

    function Get-MD5($Path) {
        function Compute-MD5($Path) {
            $md5 = [MD5]::Create()
            $stream = [File]::OpenRead($Path)
            try {
                $hash = $md5.ComputeHash($stream)
                return ([BitConverter]::ToString($hash) -replace '-', '').ToLower()
            } finally {
                if ($stream) { $stream.Dispose() }
                if ($md5) { $md5.Dispose() }
            }
        }

        try {
            # Check if the drive is accessible; if not, wait and retry until available
            $drive = ([System.IO.Path]::GetPathRoot($Path))
            while (-not (Test-Path $drive) -or -not ([System.IO.File]::Exists($Path))) {
                if (-not (Test-Path $drive)) {
                    Write-Warning "Drive $drive is not accessible. Waiting 30 seconds before retrying..."
                } elseif (-not ([System.IO.File]::Exists($Path))) {
                    Write-Warning "File not found or inaccessible: $Path. Waiting 30 seconds before retrying..."
                }
                Start-Sleep -Seconds 30
            }

            return Compute-MD5 $Path
        } catch {
            $maxRetries = 2
            $retryDelay = 5
            $attempt = 0
            $errorMsg = $_.Exception.Message
            if ($errorMsg -like "*A device attached to the system is not functioning*") {
                while ($attempt -lt $maxRetries) {
                    $attempt++
                    Write-Warning "Attempt ${attempt}: Device not functioning for '$Path'. Retrying in $retryDelay seconds due to possible cloud/network delay..."
                    Start-Sleep -Seconds $retryDelay
                    try {
                        return Compute-MD5 $Path
                    } catch {
                        $errorMsg = $_.Exception.Message
                        if ($errorMsg -notlike "*A device attached to the system is not functioning*") {
                            break
                        }
                    }
                }
                Write-Warning "Failed after $maxRetries retries: Device not functioning for '$Path'."
                Write-Warning "  └─ Error Message: $errorMsg"
                Write-Warning "  └─ Path length: $($Path.Length) characters"
                if ($Path -like "*Egnyte*" -or $Path -like "*OneDrive*" -or $Path -like "*Dropbox*") {
                    Write-Warning "  └─ Cloud storage file detected - may not be synced locally or accessible"
                }
                if ($Path.Length -gt 260) {
                    Write-Warning "  └─ Path exceeds 260 character limit - this may cause access issues"
                }
                if ($Path -match '[^\x00-\x7F]' -or $Path -match '[\[\]{}()]') {
                    Write-Warning "  └─ Special characters or Unicode detected in path - this may cause issues"
                }
                return "ERROR_DEVICE_NOT_FUNCTIONING"
            } else {
                Write-Warning "Error calculating MD5 for '$Path': $errorMsg"
                Write-Warning "  └─ Error Type: $($_.Exception.GetType().Name)"
                Write-Warning "  └─ Path length: $($Path.Length) characters"
                if ($Path -like "*Egnyte*" -or $Path -like "*OneDrive*" -or $Path -like "*Dropbox*") {
                    Write-Warning "  └─ Cloud storage file detected - may not be synced locally or accessible"
                }
                if ($Path.Length -gt 260) {
                    Write-Warning "  └─ Path exceeds 260 character limit - this may cause access issues"
                }
                if ($Path -match '[^\x00-\x7F]' -or $Path -match '[\[\]{}()]') {
                    Write-Warning "  └─ Special characters or Unicode detected in path - this may cause issues"
                }
                return "ERROR_CALCULATING_MD5"
            }
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

    $results | Export-Csv -Path (Join-Path -Path $DestinationPath ChildPath "comparison-results.csv") -NoTypeInformation
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