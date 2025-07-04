using namespace System.Net

function Invoke-AddQuarantinePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Spamfilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Tenants = ($Request.body.selectedTenants).value

    # If allTenants is selected, get all tenants and overwrite any other tenant selection
    if ('AllTenants' -in $Tenants) {
        $tenants = (Get-Tenants).defaultDomainName
    }

    $Result = foreach ($TenantFilter in $tenants) {
        try {
            $ReleaseActionPreference = $Request.Body.ReleaseActionPreference.value ?? $Request.Body.ReleaseActionPreference

            $EndUserQuarantinePermissions = @{
                PermissionToBlockSender    = $Request.Body.BlockSender
                PermissionToDelete         = $Request.Body.Delete
                PermissionToPreview        = $Request.Body.Preview
                PermissionToRelease        = $ReleaseActionPreference -eq 'Release' ? $true : $false
                PermissionToRequestRelease = $ReleaseActionPreference -eq 'RequestRelease' ? $true : $false
                PermissionToAllowSender    = $Request.Body.AllowSender
            }

            $Params = @{
                Identity                                = $Request.Body.Name
                EndUserQuarantinePermissions            = $EndUserQuarantinePermissions
                ESNEnabled                              = $Request.Body.QuarantineNotification
                IncludeMessagesFromBlockedSenderAddress = $Request.Body.IncludeMessagesFromBlockedSenderAddress
                action                                  = 'New'
                tenantFilter                            = $TenantFilter
                APIName                                 = $APIName
                Headers                                 = $Headers
            }

            Set-CIPPQuarantinePolicy @Params

        } catch {
            $_.Exception.Message
        }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = @($Result) }
    }
}
