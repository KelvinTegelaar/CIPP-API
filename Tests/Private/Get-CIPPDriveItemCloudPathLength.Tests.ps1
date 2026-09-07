BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDriveItemCloudPathLength.ps1')
}

Describe 'Get-CIPPDriveItemCloudPathLength' {
    It 'returns name length for root children' {
        Get-CIPPDriveItemCloudPathLength -ParentPath '/drives/b!abc/root:' -Name 'file.docx' | Should -Be 9
    }

    It 'includes nested folders after root:' {
        # Folder/Sub/file.docx = 6+1+3+1+9 = 20
        Get-CIPPDriveItemCloudPathLength -ParentPath '/drives/b!abc/root:/Folder/Sub' -Name 'file.docx' | Should -Be 20
    }

    It 'URL-decodes before measuring' {
        # "My Folder"/a.txt -> My Folder/a.txt = 9+1+5 = 15
        Get-CIPPDriveItemCloudPathLength -ParentPath '/drive/root:/My%20Folder' -Name 'a.txt' | Should -Be 15
    }

    It 'returns 0 for empty name' {
        Get-CIPPDriveItemCloudPathLength -ParentPath '/drive/root:/X' -Name '' | Should -Be 0
    }
}

Describe 'inferred local + cloud threshold' {
    It 'combines tenant-fixed root length with UPN local-part and cloud path' {
        $Org = 'Contoso'
        $Fixed = ('C:\Users\').Length + ("\OneDrive - $Org\").Length
        $LocalPart = 'user'
        $Cloud = 250
        $Inferred = $Fixed + $LocalPart.Length + $Cloud
        ($Inferred -gt 260) | Should -Be $true
        ($Cloud -gt 400) | Should -Be $false
    }
}
