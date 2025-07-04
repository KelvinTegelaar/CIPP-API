using namespace System.Net
function Invoke-ExecGDAPRemoveGArole {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    $GdapID = $Request.Query.GDAPId ?? $Request.Body.GDAPId
    try {
        $CheckActive = New-GraphGetRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($GdapID)" -tenantid $env:TenantID
        if ($CheckActive.status -eq 'active' -and '62e90394-69f5-4237-9190-012177145e10' -in $CheckActive.accessDetails.unifiedRoles.roleDefinitionId) {
            $AddedHeader = @{'If-Match' = $CheckActive.'@odata.etag' }

            $RawJSON = [pscustomobject]@{
                accessDetails = [pscustomobject]@{
                    unifiedRoles = @(
                        ($CheckActive.accessDetails.unifiedRoles | Where-Object { $_.roleDefinitionId -ne '62e90394-69f5-4237-9190-012177145e10' })
                    )
                }
            } | ConvertTo-Json -Depth 3

            New-GraphPOSTRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($GdapID)" -tenantid $env:TenantID -type PATCH -body $RawJSON -AddedHeaders $AddedHeader

            $Message = "Removed Global Administrator from $($GdapID)"
            Write-LogMessage -headers $Headers -API $APINAME -message $Message -Sev 'Info'
        } else {
            if ($CheckActive.status -ne 'active') {
                $Message = "Relationship status is currently $($CheckActive.status), it is not possible to remove the Global Administrator role in this state."
            }
            if ('62e90394-69f5-4237-9190-012177145e10' -notin $CheckActive.accessDetails.unifiedRoles.roleDefinitionId) {
                $Message = 'This relationship does not contain the Global Administrator role.'
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Unexpected error patching GDAP relationship: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $env:TenantID -message "$($Message): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Message = $Message }
    }
}
