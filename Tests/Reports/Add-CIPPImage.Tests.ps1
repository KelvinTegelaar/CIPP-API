# Pester tests for Add-CIPPImage.
#
# The size ceiling is a payload-size policy rather than a storage limit — Add-CIPPAzDataTableEntity
# splits oversized entities across part rows — so it is enforced here and nowhere else on the
# backend. It has to be checked against the decoded bytes: checking the data URL would reject an
# image about a quarter smaller than the stated limit, since base64 inflates by roughly a third.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Add-CIPPImage.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Add-CIPPImage.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) @{} }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:SavedEntity = $Entity }

    . $FunctionPath

    function New-DataUrl {
        param([int]$Bytes = 16, [string]$Type = 'png')
        $Payload = [byte[]]::new($Bytes)
        return "data:image/$Type;base64,$([Convert]::ToBase64String($Payload))"
    }
}

Describe 'Add-CIPPImage' {
    BeforeEach { $script:SavedEntity = $null }

    Context 'Accepted input' {
        It 'stores a small PNG and returns its id' {
            $Result = Add-CIPPImage -PartitionKey 'logo' -Data (New-DataUrl)

            $Result.id | Should -Not -BeNullOrEmpty
            $Result.partitionKey | Should -Be 'logo'
            $Result.contentType | Should -Be 'image/png'
            $script:SavedEntity.PartitionKey | Should -Be 'logo'
        }

        It 'derives the content type from the data URL' {
            (Add-CIPPImage -PartitionKey 'brandingCover' -Data (New-DataUrl -Type 'jpeg')).contentType |
                Should -Be 'image/jpeg'
        }

        It 'accepts svg+xml, whose subtype contains a character class of its own' {
            (Add-CIPPImage -PartitionKey 'logo' -Data (New-DataUrl -Type 'svg+xml')).contentType |
                Should -Be 'image/svg+xml'
        }

        It 'stores the original data URL, not just the decoded bytes' {
            $Url = New-DataUrl
            Add-CIPPImage -PartitionKey 'logo' -Data $Url | Out-Null
            $script:SavedEntity.data | Should -Be $Url
        }

        It 'gives each upload a distinct id' {
            $First = Add-CIPPImage -PartitionKey 'logo' -Data (New-DataUrl)
            $Second = Add-CIPPImage -PartitionKey 'logo' -Data (New-DataUrl)
            $First.id | Should -Not -Be $Second.id
        }
    }

    Context 'Size limit' {
        It 'accepts an image exactly on the 5MB limit' {
            { Add-CIPPImage -PartitionKey 'brandingCover' -Data (New-DataUrl -Bytes 5242880) } |
                Should -Not -Throw
        }

        It 'rejects an image one byte over the limit' {
            { Add-CIPPImage -PartitionKey 'brandingCover' -Data (New-DataUrl -Bytes 5242881) } |
                Should -Throw '*less than 5MB*'
        }

        It 'measures decoded bytes, so a 4MB image is not rejected for its base64 size' {
            # 4MB decoded is ~5.33MB as base64 — a check against the encoded string would fail this.
            { Add-CIPPImage -PartitionKey 'brandingCover' -Data (New-DataUrl -Bytes 4194304) } |
                Should -Not -Throw
        }

        It 'does not write anything when the image is too large' {
            try { Add-CIPPImage -PartitionKey 'logo' -Data (New-DataUrl -Bytes 6000000) } catch {}
            $script:SavedEntity | Should -BeNullOrEmpty
        }
    }

    Context 'Rejected input' {
        It 'rejects a non-image data URL' {
            { Add-CIPPImage -PartitionKey 'logo' -Data 'data:text/html;base64,PGh0bWw+' } |
                Should -Throw '*Invalid image format*'
        }

        It 'rejects a bare URL' {
            { Add-CIPPImage -PartitionKey 'logo' -Data 'https://example.com/logo.png' } |
                Should -Throw '*Invalid image format*'
        }

        It 'rejects malformed base64 rather than storing an unreadable image' {
            { Add-CIPPImage -PartitionKey 'logo' -Data 'data:image/png;base64,not!valid!base64!' } |
                Should -Throw '*Invalid base64*'
        }

        It 'rejects an empty payload' {
            { Add-CIPPImage -PartitionKey 'logo' -Data '' } | Should -Throw
        }
    }
}
