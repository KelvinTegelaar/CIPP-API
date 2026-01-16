function Add-CippTestResult {
    <#
    .SYNOPSIS
        Adds a test result to the CIPP test results database

    .DESCRIPTION
        Stores test result data in the CippTestResults table with tenant and test ID as keys

    .PARAMETER TenantFilter
        The tenant domain or GUID for the test result

    .PARAMETER TestId
        Unique identifier for the test

    .PARAMETER Status
        Test status (e.g., Pass, Fail, Skip)

    .PARAMETER ResultMarkdown
        Markdown formatted result details

    .PARAMETER Risk
        Risk level (e.g., High, Medium, Low)

    .PARAMETER Name
        Display name of the test

    .PARAMETER Pillar
        Security pillar category

    .PARAMETER UserImpact
        Impact level on users

    .PARAMETER ImplementationEffort
        Effort required for implementation

    .PARAMETER Category
        Test category or classification

    .EXAMPLE
        Add-CippTestResult -TenantFilter 'contoso.onmicrosoft.com' -TestId 'MFA-001' -Status 'Pass' -Name 'MFA Enabled' -Risk 'High'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$TestId,

        [Parameter(Mandatory = $false)]
        [string]$testType = 'Identity',

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$ResultMarkdown,

        [Parameter(Mandatory = $false)]
        [string]$Risk,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Pillar,

        [Parameter(Mandatory = $false)]
        [string]$UserImpact,

        [Parameter(Mandatory = $false)]
        [string]$ImplementationEffort,

        [Parameter(Mandatory = $false)]
        [string]$Category
    )

    try {
        $Table = Get-CippTable -tablename 'CippTestResults'

        $Entity = @{
            PartitionKey         = $TenantFilter
            RowKey               = $TestId
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown ?? ''
            Risk                 = $Risk ?? ''
            Name                 = $Name ?? ''
            Pillar               = $Pillar ?? ''
            UserImpact           = $UserImpact ?? ''
            ImplementationEffort = $ImplementationEffort ?? ''
            Category             = $Category ?? ''
            TestType             = $TestType
        }

        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        Write-LogMessage -API 'CIPPTestResults' -tenant $TenantFilter -message "Added test result: $TestId - $Status" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPTestResults' -tenant $TenantFilter -message "Failed to add test result: $($_.Exception.Message)" -sev Error
        throw
    }
}
