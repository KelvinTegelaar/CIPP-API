# Pester tests for Get-NormalizedError

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-NormalizedError.ps1')
}

Describe 'Get-NormalizedError' {
    It 'surfaces the inner details when the inner message only says to see them' {
        $Body = '{"error":{"code":"badRequest","message":"Cannot process the request because it is malformed or incorrect.","innerError":{"code":"invalidInput","message":"There were issue(s) with the input. See details for more information.","details":[{"code":"invalidValue","message":"One or more role IDs are duplicated","target":"accessDetails.unifiedRoles"}]}}}'
        Get-NormalizedError -Message $Body | Should -Be 'One or more role IDs are duplicated'
    }

    It 'keeps a specific inner message' {
        $Body = '{"error":{"code":"badRequest","message":"Bad request","innerError":{"message":"One or more unified role definition IDs specified are not recognized/supported."}}}'
        Get-NormalizedError -Message $Body | Should -Be 'One or more unified role definition IDs specified are not recognized/supported.'
    }
}
