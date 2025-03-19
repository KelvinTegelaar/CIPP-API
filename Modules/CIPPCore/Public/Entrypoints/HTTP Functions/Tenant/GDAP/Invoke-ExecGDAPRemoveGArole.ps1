using namespace System.Net
Function Invoke-ExecGDAPRemoveGArole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $GDAPID = $request.query.GDAPId ?? $request.Body.GDAPId

    try {
        $CheckActive = New-GraphGetRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($GDAPID)" -tenantid $env:TenantID
        if ($CheckActive.status -eq 'active' -AND '62e90394-69f5-4237-9190-012177145e10' -in $CheckActive.accessDetails.unifiedRoles.roleDefinitionId) {
            $AddedHeader = @{'If-Match' = $CheckActive.'@odata.etag' }

            $RawJSON = [pscustomobject]@{
                accessDetails = [pscustomobject]@{
                    unifiedRoles = @(
                        ($CheckActive.accessDetails.unifiedRoles | Where-Object { $_.roleDefinitionId -ne '62e90394-69f5-4237-9190-012177145e10' })
                    )
                }
            } | ConvertTo-Json -Depth 3

            New-GraphPOSTRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($GDAPID)" -tenantid $env:TenantID -type PATCH -body $RawJSON -AddedHeaders $AddedHeader

            $Message = "Removed Global Administrator from $($GDAPID)"
            Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Info'
        } else {
            if ($CheckActive.status -ne 'active') {
                $Message = "Relationship status is currently $($CheckActive.status), it is not possible to remove the Global Administrator role in this state."
            }
            if ('62e90394-69f5-4237-9190-012177145e10' -notin $CheckActive.accessDetails.unifiedRoles.roleDefinitionId) {
                $Message = 'This relationship does not contain the Global Administrator role.'
            }
        }
    } catch {
        $Message = "Unexpected error patching GDAP relationship: $($_.Exception.Message)"
        Write-Host "GDAP ERROR: $($_.Exception.Message)"
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $env:TenantID -message "$($Message): $($_.Exception.Message)" -Sev 'Error'
    }

    $body = @{
        Message = $Message
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
