function Invoke-ExecManageAppCredentials {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Body.tenantFilter
    $Action = $Request.Body.Action
    $AppType = $Request.Body.AppType           # applications | servicePrincipals
    $CredentialType = $Request.Body.CredentialType # password | key
    $KeyId = $Request.Body.KeyId
    $AppId = $Request.Body.AppId
    $Id = $Request.Body.Id

    $IdPath = if ($Id) { "/$Id" } else { "(appId='$AppId')" }
    $Uri = "https://graph.microsoft.com/beta/$AppType$IdPath"

    try {
        $Results = switch ($Action) {
            'Remove' {
                if ($CredentialType -eq 'password') {
                    $null = New-GraphPOSTRequest -Uri "$Uri/removePassword" -Body (@{ keyId = $KeyId } | ConvertTo-Json) -tenantid $TenantFilter
                    @{ resultText = "Successfully removed password credential $KeyId"; state = 'success' }
                } else {
                    # Certificates can't use removeKey without a proof JWT, so PATCH the array instead
                    $Current = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter
                    $Updated = @($Current.keyCredentials | Where-Object { $_.keyId -ne $KeyId })
                    $null = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body (@{ keyCredentials = $Updated } | ConvertTo-Json -Depth 10) -tenantid $TenantFilter
                    @{ resultText = "Successfully removed key credential $KeyId"; state = 'success' }
                }
            }
            'Add' {
                # TODO: implement credential addition
                @{ resultText = 'Add not yet implemented'; state = 'info' }
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Results }
            })
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = @{ resultText = "Failed to $Action credential: $($_.Exception.Message)"; state = 'error' } }
            })
    }
}
