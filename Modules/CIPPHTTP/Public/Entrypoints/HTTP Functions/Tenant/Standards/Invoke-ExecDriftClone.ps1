function Invoke-ExecDriftClone {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint ?? 'ExecDriftClone'
    $Headers = $Request.Headers

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
        $CloneResult = New-CippStandardsDriftClone -TemplateId $TemplateId -UpgradeToDrift
        if ($CloneResult -like 'Failed*') {
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $CloneResult -Sev 'Error'
            $Results = [pscustomobject]@{
                'Results' = $CloneResult
                'Success' = $false
            }
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = $Results
                })
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $CloneResult -Sev 'Info'
        $Results = [pscustomobject]@{
            'Results' = 'Clone Completed successfully'
            'Success' = $true
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to create drift clone: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
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
