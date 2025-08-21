using namespace System.Net

function Invoke-ExecDriftClone {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $TemplateId = $Request.Body.id

        if (-not $TemplateId) {
            $Results = [pscustomobject]@{
                'Results' = 'Template ID is required'
                'Success' = $false
            }
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = $Results
                })
            return
        }
        $CloneResult = New-CippStandardsDriftClone -TemplateId $TemplateId -UpgradeToDrift -Headers $Request.Headers
        $Results = [pscustomobject]@{
            'Results' = $CloneResult
            'Success' = $true
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
            })
    } catch {
        $Results = [pscustomobject]@{
            'Results' = "Failed to create drift clone: $($_.Exception.Message)"
            'Success' = $false
        }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $Results
            })
    }
}
