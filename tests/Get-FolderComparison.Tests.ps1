BeforeAll {
    # Import the module for testing
    $ModulePath = Join-Path $PSScriptRoot '..' 'Get-FolderComparison.psd1'
    Import-Module $ModulePath -Force
    
    # Create test directories
    $TestRoot = Join-Path $PSScriptRoot 'TestData'
    $SourcePath = Join-Path $TestRoot 'Source'
    $DestinationPath = Join-Path $TestRoot 'Destination'
    
    # Ensure test directories exist
    if (-not (Test-Path $TestRoot)) { New-Item -ItemType Directory -Path $TestRoot -Force }
    if (-not (Test-Path $SourcePath)) { New-Item -ItemType Directory -Path $SourcePath -Force }
    if (-not (Test-Path $DestinationPath)) { New-Item -ItemType Directory -Path $DestinationPath -Force }
}

AfterAll {
    # Clean up test data
    $TestRoot = Join-Path $PSScriptRoot 'TestData'
    if (Test-Path $TestRoot) {
        Remove-Item $TestRoot -Recurse -Force
    }
    
    # Remove the module
    Remove-Module Get-FolderComparison -Force -ErrorAction SilentlyContinue
}

Describe "Get-FolderComparison" {
    BeforeEach {
        # Clean test directories before each test
        $TestRoot = Join-Path $PSScriptRoot 'TestData'
        $SourcePath = Join-Path $TestRoot 'Source'
        $DestinationPath = Join-Path $TestRoot 'Destination'
        
        if (Test-Path $SourcePath) { Remove-Item $SourcePath -Recurse -Force }
        if (Test-Path $DestinationPath) { Remove-Item $DestinationPath -Recurse -Force }
        
        New-Item -ItemType Directory -Path $SourcePath -Force
        New-Item -ItemType Directory -Path $DestinationPath -Force
    }
    
    Context "Basic Functionality" {
        It "Should return empty results for empty directories" {
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -BeNullOrEmpty
        }
        
        It "Should detect unchanged files" {
            # Create identical files
            $testFile = Join-Path $SourcePath 'test.txt'
            $destFile = Join-Path $DestinationPath 'test.txt'
            'Hello World' | Out-File -FilePath $testFile -Encoding UTF8
            'Hello World' | Out-File -FilePath $destFile -Encoding UTF8
            
            # Set same timestamps
            $timestamp = Get-Date
            (Get-Item $testFile).LastWriteTimeUtc = $timestamp
            (Get-Item $destFile).LastWriteTimeUtc = $timestamp
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Unchanged"
        }
        
        It "Should detect updated files" {
            # Create files with different content
            $testFile = Join-Path $SourcePath 'test.txt'
            $destFile = Join-Path $DestinationPath 'test.txt'
            'Hello World' | Out-File -FilePath $testFile -Encoding UTF8
            'Hello World Updated' | Out-File -FilePath $destFile -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Updated"
        }
        
        It "Should detect added files" {
            # Create file only in destination
            $destFile = Join-Path $DestinationPath 'new.txt'
            'New File' | Out-File -FilePath $destFile -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Added"
        }
        
        It "Should detect removed files" {
            # Create file only in source
            $srcFile = Join-Path $SourcePath 'removed.txt'
            'Removed File' | Out-File -FilePath $srcFile -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Removed"
        }
        
        It "Should detect moved files" {
            # Create file in source root and destination subfolder
            $srcFile = Join-Path $SourcePath 'test.txt'
            $destSubdir = Join-Path $DestinationPath 'subfolder'
            $destFile = Join-Path $destSubdir 'test.txt'
            
            New-Item -ItemType Directory -Path $destSubdir -Force
            'Test Content' | Out-File -FilePath $srcFile -Encoding UTF8
            'Test Content' | Out-File -FilePath $destFile -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Moved"
        }
        
        It "Should detect renamed files" {
            # Create files with same content but different names in same location
            $srcFile = Join-Path $SourcePath 'oldname.txt'
            $destFile = Join-Path $DestinationPath 'newname.txt'
            
            'Test Content' | Out-File -FilePath $srcFile -Encoding UTF8
            'Test Content' | Out-File -FilePath $destFile -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Renamed"
        }
        
        It "Should detect moved and renamed files" {
            # Create file in source root and different name in destination subfolder
            $srcFile = Join-Path $SourcePath 'original.txt'
            $destSubdir = Join-Path $DestinationPath 'newfolder'
            $destFile = Join-Path $destSubdir 'renamed.txt'
            
            New-Item -ItemType Directory -Path $destSubdir -Force
            'Test Content' | Out-File -FilePath $srcFile -Encoding UTF8
            'Test Content' | Out-File -FilePath $destFile -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "MovedAndRenamed"
        }
        
        It "Should detect likely renamed files with similar names" {
            # Create files with very similar names in same directory but different content
            # Use names that are close enough to trigger similarity matching
            $srcFile = Join-Path $SourcePath 'report.txt'
            $destFile = Join-Path $DestinationPath 'report1.txt'
            
            'Original Content' | Out-File -FilePath $srcFile -Encoding UTF8
            'Different Content' | Out-File -FilePath $destFile -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            # Should detect as likely renamed since names are similar but content differs
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "LikelyRenamedOrUpdated"
        }
        
        It "Should detect unchanged files with same size and timestamp" {
            # Create files with same content, size, and timestamp (skip MD5 calculation)
            $srcFile = Join-Path $SourcePath 'test.txt'
            $destFile = Join-Path $DestinationPath 'test.txt'
            $content = 'Test Content'
            
            $content | Out-File -FilePath $srcFile -Encoding UTF8 -NoNewline
            $content | Out-File -FilePath $destFile -Encoding UTF8 -NoNewline
            
            # Set identical timestamps and sizes
            $timestamp = Get-Date
            $srcItem = Get-Item $srcFile
            $destItem = Get-Item $destFile
            $srcItem.LastWriteTimeUtc = $timestamp
            $destItem.LastWriteTimeUtc = $timestamp
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Unchanged"
        }
        
        It "Should detect unchanged files with same content but different timestamps" {
            # Create files with same content but different timestamps to force MD5 comparison
            $srcFile = Join-Path $SourcePath 'test.txt'
            $destFile = Join-Path $DestinationPath 'test.txt'
            $content = 'Test Content for MD5 check'
            
            $content | Out-File -FilePath $srcFile -Encoding UTF8
            $content | Out-File -FilePath $destFile -Encoding UTF8
            
            # Set different timestamps to force MD5 calculation path
            $srcItem = Get-Item $srcFile
            $destItem = Get-Item $destFile
            $srcItem.LastWriteTimeUtc = (Get-Date).AddHours(-1)
            $destItem.LastWriteTimeUtc = Get-Date
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Unchanged"
        }
    }
    
    Context "Parameter Validation" {
        It "Should throw when SourcePath does not exist" {
            { Get-FolderComparison -SourcePath "C:\NonExistent" -DestinationPath $DestinationPath } | Should -Throw
        }
        
        It "Should throw when DestinationPath does not exist" {
            { Get-FolderComparison -SourcePath $SourcePath -DestinationPath "C:\NonExistent" } | Should -Throw
        }
    }
    
    Context "Complex Scenarios" {
        It "Should handle nested directory structures" {
            # Create nested structure
            $srcSubdir = Join-Path $SourcePath 'level1\level2'
            $destSubdir = Join-Path $DestinationPath 'level1\level2'
            
            New-Item -ItemType Directory -Path $srcSubdir -Force
            New-Item -ItemType Directory -Path $destSubdir -Force
            
            $srcFile = Join-Path $srcSubdir 'nested.txt'
            $destFile = Join-Path $destSubdir 'nested.txt'
            
            'Nested Content' | Out-File -FilePath $srcFile -Encoding UTF8
            'Nested Content' | Out-File -FilePath $destFile -Encoding UTF8
            
            # Set same timestamps
            $timestamp = Get-Date
            (Get-Item $srcFile).LastWriteTimeUtc = $timestamp
            (Get-Item $destFile).LastWriteTimeUtc = $timestamp
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "Unchanged"
            $result[0].RelativePath | Should -Be "level1\level2\nested.txt"
        }
        
        It "Should handle files with similar names in nested directories" {
            # Create nested structure with similar names
            $srcSubdir = Join-Path $SourcePath 'docs'
            $destSubdir = Join-Path $DestinationPath 'docs'
            
            New-Item -ItemType Directory -Path $srcSubdir -Force
            New-Item -ItemType Directory -Path $destSubdir -Force
            
            $srcFile = Join-Path $srcSubdir 'report_v1.txt'
            $destFile = Join-Path $destSubdir 'report_v2.txt'
            
            'Original Report' | Out-File -FilePath $srcFile -Encoding UTF8
            'Updated Report' | Out-File -FilePath $destFile -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 1
            $result[0].Type | Should -Be "LikelyRenamedOrUpdated"
        }
        
        It "Should handle multiple files with mixed operations" {
            # Create a complex scenario with multiple operations
            $srcSubdir = Join-Path $SourcePath 'project'
            $destSubdir = Join-Path $DestinationPath 'project'
            $destSubdir2 = Join-Path $DestinationPath 'archive'
            
            New-Item -ItemType Directory -Path $srcSubdir -Force
            New-Item -ItemType Directory -Path $destSubdir -Force  
            New-Item -ItemType Directory -Path $destSubdir2 -Force
            
            # Unchanged file
            $srcFile1 = Join-Path $srcSubdir 'readme.txt'
            $destFile1 = Join-Path $destSubdir 'readme.txt'
            'README' | Out-File -FilePath $srcFile1 -Encoding UTF8
            'README' | Out-File -FilePath $destFile1 -Encoding UTF8
            $timestamp = Get-Date
            (Get-Item $srcFile1).LastWriteTimeUtc = $timestamp
            (Get-Item $destFile1).LastWriteTimeUtc = $timestamp
            
            # Moved file
            $srcFile2 = Join-Path $srcSubdir 'config.json'
            $destFile2 = Join-Path $destSubdir2 'config.json'
            '{"setting": "value"}' | Out-File -FilePath $srcFile2 -Encoding UTF8
            '{"setting": "value"}' | Out-File -FilePath $destFile2 -Encoding UTF8
            
            # Renamed file  
            $srcFile3 = Join-Path $srcSubdir 'temp.log'
            $destFile3 = Join-Path $destSubdir 'application.log'
            'Log entry' | Out-File -FilePath $srcFile3 -Encoding UTF8
            'Log entry' | Out-File -FilePath $destFile3 -Encoding UTF8
            
            # Removed file
            $srcFile4 = Join-Path $srcSubdir 'old.txt'
            'Old file' | Out-File -FilePath $srcFile4 -Encoding UTF8
            
            # Added file (use a very different name to avoid similarity matching)
            $destFile5 = Join-Path $destSubdir 'completely_different_file.txt'
            'New file' | Out-File -FilePath $destFile5 -Encoding UTF8
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 5
            
            # Verify each type is detected
            $unchanged = $result | Where-Object { $_.Type -eq "Unchanged" }
            $moved = $result | Where-Object { $_.Type -eq "Moved" }
            $renamed = $result | Where-Object { $_.Type -eq "Renamed" }
            $removed = $result | Where-Object { $_.Type -eq "Removed" }
            $added = $result | Where-Object { $_.Type -eq "Added" }
            
            $unchanged | Should -HaveCount 1
            $moved | Should -HaveCount 1
            $renamed | Should -HaveCount 1
            $removed | Should -HaveCount 1
            $added | Should -HaveCount 1
        }
        
        It "Should detect removed duplicates" {
            # Create scenario where a file is removed but exists as duplicate in destination
            $srcFile1 = Join-Path $SourcePath 'document.txt'
            $srcFile2 = Join-Path $SourcePath 'copy_of_document.txt'
            $destFile1 = Join-Path $DestinationPath 'document.txt'
            
            $content = 'Same content in all files'
            $content | Out-File -FilePath $srcFile1 -Encoding UTF8
            $content | Out-File -FilePath $srcFile2 -Encoding UTF8
            $content | Out-File -FilePath $destFile1 -Encoding UTF8
            
            # Set same timestamp for identical files
            $timestamp = Get-Date
            (Get-Item $srcFile1).LastWriteTimeUtc = $timestamp
            (Get-Item $destFile1).LastWriteTimeUtc = $timestamp
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 2
            
            # Should have one unchanged and one removed duplicate
            $unchanged = $result | Where-Object { $_.Type -eq "Unchanged" }
            $removedDuplicate = $result | Where-Object { $_.Type -eq "RemovedDuplicate" }
            
            $unchanged | Should -HaveCount 1
            $removedDuplicate | Should -HaveCount 1
            $removedDuplicate.DuplicateOf | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect duplicate files in destination" {
            # Create scenario with duplicate files in destination
            $srcFile = Join-Path $SourcePath 'original.txt'
            $destFile1 = Join-Path $DestinationPath 'original.txt'
            $destFile2 = Join-Path $DestinationPath 'duplicate.txt'
            
            $content = 'Content that will be duplicated'
            $content | Out-File -FilePath $srcFile -Encoding UTF8
            $content | Out-File -FilePath $destFile1 -Encoding UTF8
            $content | Out-File -FilePath $destFile2 -Encoding UTF8
            
            # Set same timestamp for identical files
            $timestamp = Get-Date
            (Get-Item $srcFile).LastWriteTimeUtc = $timestamp
            (Get-Item $destFile1).LastWriteTimeUtc = $timestamp
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            $result | Should -HaveCount 2
            
            # Should have one unchanged and one added (marked as duplicate)
            $unchanged = $result | Where-Object { $_.Type -eq "Unchanged" }
            $added = $result | Where-Object { $_.Type -eq "Added" }
            
            $unchanged | Should -HaveCount 1
            $added | Should -HaveCount 1
            $added.DuplicateOf | Should -Not -BeNullOrEmpty
        }
        
        It "Should assign unique indices to all results" {
            # Create multiple files to verify indexing
            $srcFile1 = Join-Path $SourcePath 'file1.txt'
            $srcFile2 = Join-Path $SourcePath 'file2.txt'
            $destFile1 = Join-Path $DestinationPath 'file1.txt'
            $destFile3 = Join-Path $DestinationPath 'file3.txt'
            
            'Content 1' | Out-File -FilePath $srcFile1 -Encoding UTF8
            'Content 2' | Out-File -FilePath $srcFile2 -Encoding UTF8
            'Content 1' | Out-File -FilePath $destFile1 -Encoding UTF8
            'Content 3' | Out-File -FilePath $destFile3 -Encoding UTF8
            
            # Set same timestamp for file1
            $timestamp = Get-Date
            (Get-Item $srcFile1).LastWriteTimeUtc = $timestamp
            (Get-Item $destFile1).LastWriteTimeUtc = $timestamp
            
            $result = Get-FolderComparison -SourcePath $SourcePath -DestinationPath $DestinationPath
            
            # All results should have unique, sequential indices
            $indices = $result | ForEach-Object { $_.Index } | Sort-Object
            $indices | Should -HaveCount $result.Count
            $indices[0] | Should -Be 1
            $indices[-1] | Should -Be $result.Count
            
            # No duplicate indices
            ($indices | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        }
    }
}
