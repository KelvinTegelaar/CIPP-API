# The permission batches project EXO responses with $select. A field the code reads but the
# projection omits comes back $null with no error, so every $Perm.<Field> read must be selected.

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Mailbox Permissions'
    $script:Cases = foreach ($Name in 'Push-GetMailboxPermissionsBatch', 'Push-GetCalendarPermissionsBatch') {
        $Source = Get-Content -Raw -Path (Join-Path $Folder "$Name.ps1")
        $Select = [regex]::Match($Source, '-cmdletArray @\(\$(ExoBulkRequests|PermissionRequests)\)[^\r\n]*-Select ''([^'']+)''').Groups[2].Value
        $Read = @([regex]::Matches($Source, '\$Perm\.([A-Za-z]+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notin 'error', 'OperationGuid' } | Sort-Object -Unique)
        @{ Name = $Name; Select = $Select; Read = $Read }
    }
}

Describe 'Mailbox permission $select projections' {
    It '<Name> selects every field it reads' -ForEach $script:Cases {
        $Select | Should -Not -BeNullOrEmpty
        $Read.Count | Should -BeGreaterThan 2
        foreach ($Field in $Read) { $Select -split ',' | Should -Contain $Field -Because "$Name reads `$Perm.$Field" }
    }
}
