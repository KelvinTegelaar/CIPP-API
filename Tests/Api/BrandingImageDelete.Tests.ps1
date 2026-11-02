# Pester tests for the id-list bookkeeping in Invoke-ExecBrandingSettings' DeleteImage action.
#
# Deleting one image must remove exactly that id from the gallery list. The list is stored as JSON
# and read back through ConvertTo-CIPPCoverImageIdList, which returns the array comma-wrapped so a
# one-element result cannot unwrap to a scalar. Filtering that wrapper through a pipeline hands
# Where-Object the whole array as a single item, and the surviving ids get serialised space-joined
# into one bogus id - which resolves to nothing on the next read and empties the whole gallery.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ConverterPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'ConvertTo-CIPPCoverImageIdList.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ConverterPath) { throw 'Could not locate ConvertTo-CIPPCoverImageIdList.ps1 under Modules/' }
    . $ConverterPath

    $script:EntrypointPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBrandingSettings.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $script:EntrypointPath) { throw 'Could not locate Invoke-ExecBrandingSettings.ps1 under Modules/' }

    # Mirror of the entrypoint's serialiser.
    function ConvertTo-IdListJson {
        param($Value)
        $Ids = ConvertTo-CIPPCoverImageIdList -Value $Value
        return ConvertTo-Json -InputObject ([string[]]$Ids) -Compress
    }

    # The expression the entrypoint uses to drop one id from the stored list.
    function Remove-IdFromList {
        param($Stored, $ImageId)
        $Remaining = [string[]]@((ConvertTo-CIPPCoverImageIdList -Value $Stored).Where({ $_ -ne $ImageId }))
        return ConvertTo-IdListJson -Value $Remaining
    }
}

Describe 'DeleteImage id-list bookkeeping' {
    It 'removes only the deleted id when several are stored' {
        Remove-IdFromList -Stored '["aaa","bbb","ccc"]' -ImageId 'bbb' | Should -Be '["aaa","ccc"]'
    }

    It 'never collapses the remaining ids into one space-joined value' {
        # The regression: '["aaa bbb ccc"]' resolves to nothing on the next read, so every image
        # disappears from the gallery even though the rows are still in the table.
        $Result = Remove-IdFromList -Stored '["aaa","bbb","ccc"]' -ImageId 'bbb'
        $Result | Should -Not -Match ' '
        @($Result | ConvertFrom-Json).Count | Should -Be 2
    }

    It 'empties the list when the only stored id is the one deleted' {
        Remove-IdFromList -Stored '["aaa"]' -ImageId 'aaa' | Should -Be '[]'
    }

    It 'keeps a single stored id when a different one is deleted' {
        Remove-IdFromList -Stored '["aaa"]' -ImageId 'zzz' | Should -Be '["aaa"]'
    }

    It 'leaves the list alone when the id is not in it' {
        Remove-IdFromList -Stored '["aaa","bbb"]' -ImageId 'zzz' | Should -Be '["aaa","bbb"]'
    }

    It 'handles an empty stored list' {
        Remove-IdFromList -Stored '[]' -ImageId 'aaa' | Should -Be '[]'
    }

    It 'filters the id list with .Where() rather than a pipeline' {
        # Piping the comma-wrapped array is what caused the collapse, so the shape is pinned.
        $Source = Get-Content -Path $script:EntrypointPath -Raw
        $Source | Should -Not -Match 'ConvertTo-CIPPCoverImageIdList[^\r\n]*\|[^\r\n]*Where-Object'
    }

    It 'keeps a single-element id list an array so [0] is the whole id' {
        # Get-CIPPBrandingSettings indexes LogoImageIds[0]/CoverImageIds[0] to fetch the selected
        # image. Were the one-element case to unwrap to a scalar, [0] would be the first character
        # of the GUID and the lookup would silently find nothing.
        $Ids = ConvertTo-CIPPCoverImageIdList -Value '["8759c53f-076c-4f5f-bcb4-996ff39adaef"]'
        $Ids[0] | Should -Be '8759c53f-076c-4f5f-bcb4-996ff39adaef'
    }
}
