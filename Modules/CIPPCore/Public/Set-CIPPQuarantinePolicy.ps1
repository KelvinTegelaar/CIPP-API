function Set-CIPPQuarantinePolicy {
    <#
    .SYNOPSIS
    Set/Add Quarantine policy, supports both custom and global Quarantine Policy

    .DESCRIPTION
    Set/Add Quarantine policy, supports both custom and global Quarantine Policy

    .PARAMETER identity
    Identity of the Quarantine policy to set, Name or GUID.

    .PARAMETER action
    Which action to perform Create or Update. Valid values are Add, New, Create, Edit, Set, Update.

    .PARAMETER tenantFilter
    Tenant to manage quarantine policy for.

    .PARAMETER EndUserQuarantinePermissions
    End user quarantine permissions to set. This is a hashtable with the following keys:
    PermissionToBlockSender
    PermissionToDelete
    PermissionToPreview
    PermissionToRelease
    PermissionToRequestRelease
    PermissionToAllowSender
    PermissionToViewHeader
    PermissionToDownload

    .PARAMETER APIName
    Name of the API executing the command.

    .PARAMETER ESNEnabled
    Whether the quarantine notification is enabled or not.

    .PARAMETER IncludeMessagesFromBlockedSenderAddress
    Whether to include messages from blocked sender address or not.

    #>
    [CmdletBinding(DefaultParameterSetName = 'QuarantinePolicy')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'QuarantinePolicy')]
        [Parameter(Mandatory, ParameterSetName = 'GlobalQuarantinePolicy')]
        [ValidateNotNullOrEmpty()]
        [string]$identity,

        [Parameter(Mandatory, ParameterSetName = 'QuarantinePolicy')]
        [ValidateSet("Add", "New", "Create", "Edit", "Set", "Update")]
        [string]$action,

        [Parameter(Mandatory, ParameterSetName = 'QuarantinePolicy')]
        [Hashtable]$EndUserQuarantinePermissions,

        [Parameter(Mandatory, ParameterSetName = 'QuarantinePolicy')]
        [bool]$ESNEnabled,

        [Parameter(ParameterSetName = 'QuarantinePolicy')]
        [bool]$IncludeMessagesFromBlockedSenderAddress = $false,

        [Parameter(Mandatory, ParameterSetName = 'GlobalQuarantinePolicy')]
        [TimeSpan]$EndUserSpamNotificationFrequency,

        [Parameter(ParameterSetName = 'GlobalQuarantinePolicy')]
        [string]$EndUserSpamNotificationCustomFromAddress = "",

        [Parameter(ParameterSetName = 'GlobalQuarantinePolicy')]
        [bool]$OrganizationBrandingEnabled = $false,

        [Parameter(Mandatory)]
        [string]$tenantFilter,
        [string]$APIName = 'QuarantinePolicy'
    )

    try {

        switch ($PSCmdlet.ParameterSetName) {
            "GlobalQuarantinePolicy" {
                $cmdParams = @{
                    Identity = $identity
                    EndUserSpamNotificationFrequency = $EndUserSpamNotificationFrequency.ToString()
                    EndUserSpamNotificationCustomFromAddress = $EndUserSpamNotificationCustomFromAddress
                    OrganizationBrandingEnabled = $OrganizationBrandingEnabled
                    # QuarantinePolicyType = 'GlobalQuarantinePolicy'
                }
                $cmdLet = 'Set-QuarantinePolicy'
             }
            "QuarantinePolicy" {
                $cmdParams = @{
                    EndUserQuarantinePermissionsValue = Convert-QuarantinePermissionsValue @EndUserQuarantinePermissions -ErrorAction Stop
                    ESNEnabled = $ESNEnabled
                    IncludeMessagesFromBlockedSenderAddress = $IncludeMessagesFromBlockedSenderAddress
                }

                switch ($action) {
                    {$_ -in @("Add", "New", "Create")} { $cmdParams.Add("Name", $identity) ; $cmdLet = 'New-QuarantinePolicy' }
                    {$_ -in @("Edit", "Set", "Update")} { $cmdParams.Add("Identity", $identity) ; $cmdLet = 'Set-QuarantinePolicy' }
                    Default {
                        throw "Invalid action specified. Valid actions are: Add, New, Edit, Set, Update."
                    }
                }
            }
        }

        $null = New-ExoRequest -tenantid $tenantFilter -cmdlet $cmdLet -cmdParams $cmdParams -useSystemMailbox $true

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        throw ($ErrorMessage.NormalizedError -replace '\|Microsoft.Exchange.Management.Tasks.ValidationException\|', '')
    }
}
