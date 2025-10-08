function New-CIPPAssignmentFilter {
    <#
    .SYNOPSIS
    Creates a new assignment filter in Microsoft Intune

    .DESCRIPTION
    Unified function for creating assignment filters that handles all platform types consistently.
    Used by both direct filter creation and assignment filter template application.

    .PARAMETER FilterObject
    Object containing filter properties (displayName, description, platform, rule, etc.)

    .PARAMETER TenantFilter
    The tenant domain name where the filter should be created

    .PARAMETER APIName
    The API name for logging purposes

    .PARAMETER ExecutingUser
    The user executing the request (for logging)

    .EXAMPLE
    New-CIPPAssignmentFilter -FilterObject $FilterData -TenantFilter 'contoso.com' -APIName 'AddAssignmentFilter'

    .NOTES
    Supports all platform types: Windows10AndLater, iOS, Android, macOS, etc.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$FilterObject,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$APIName = 'New-CIPPAssignmentFilter',

        [Parameter(Mandatory = $false)]
        [string]$ExecutingUser = 'CIPP'
    )

    try {
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Creating assignment filter $($FilterObject.displayName) for platform $($FilterObject.platform)" -Sev Info

        # Build the request body for Graph API
        $BodyParams = [PSCustomObject]@{
            '@odata.type'                   = '#microsoft.graph.deviceAndAppManagementAssignmentFilter'
            'displayName'                   = $FilterObject.displayName
            'description'                   = $FilterObject.description ?? ''
            'platform'                      = $FilterObject.platform
            'rule'                          = $FilterObject.rule
            'assignmentFilterManagementType' = $FilterObject.assignmentFilterManagementType ?? 'devices'
        }

        # Create the assignment filter via Graph API
        $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter -type POST -body (ConvertTo-Json -InputObject $BodyParams -Depth 10)

        $Result = [PSCustomObject]@{
            Success  = $true
            Message  = "Successfully created assignment filter $($FilterObject.displayName)"
            FilterId = $GraphRequest.id
            Platform = $FilterObject.platform
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Created assignment filter $($FilterObject.displayName) with id $($Result.FilterId)" -Sev Info
        return $Result

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Assignment filter creation failed for $($FilterObject.displayName): $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage

        return [PSCustomObject]@{
            Success  = $false
            Message  = "Failed to create assignment filter $($FilterObject.displayName): $($ErrorMessage.NormalizedError)"
            Error    = $ErrorMessage.NormalizedError
            Platform = $FilterObject.platform
        }
    }
}
