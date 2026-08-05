function Get-CippTestSuitePatterns {
    <#
    .SYNOPSIS
        Canonical suite-to-pattern map for CIPP test functions

    .DESCRIPTION
        Single source of truth for which Invoke-CippTest* functions belong to which suite.
        Pattern-based rather than path-based so it works in compiled (ModuleBuilder) images,
        where the per-test .ps1 files no longer exist on disk.

        Consumed by Invoke-CIPPTestCollection to discover a suite's tests via Get-Command, and by
        Get-CIPPTestResultsTenants to label stored results with their suite (a TestId is the
        function name minus the 'Invoke-CippTest' prefix, so the patterns apply to RowKeys once
        that prefix is stripped). The Custom suite is not listed — custom results are recognised
        by their 'CustomScript-<guid>' ids.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    return [ordered]@{
        ZTNA             = 'Invoke-CippTestZTNA*'
        ORCA             = 'Invoke-CippTestORCA*'
        EIDSCA           = 'Invoke-CippTestEIDSCA*'
        CISA             = 'Invoke-CippTestCISA*'
        CIS              = 'Invoke-CippTestCIS_*'
        SMB1001          = 'Invoke-CippTestSMB1001_*'
        CopilotReadiness = 'Invoke-CippTestCopilotReady*'
        GenericTests     = 'Invoke-CippTestGenericTest*'
        E8               = 'Invoke-CippTestE8_*'
    }
}
