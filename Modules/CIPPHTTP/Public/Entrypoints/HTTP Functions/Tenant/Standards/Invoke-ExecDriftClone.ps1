function Invoke-ExecDriftClone {
    <#
    .FUNCTIONALITY
        Entrypoint
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
            return ([HttpResponseContext]@{
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

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
            })
    } catch {
        $Results = [pscustomobject]@{
            'Results' = "Failed to create drift clone: $($_.Exception.Message)"
            'Success' = $false
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $Results
            })
    }
}
