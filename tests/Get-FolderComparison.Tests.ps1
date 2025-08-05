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
    }
}
