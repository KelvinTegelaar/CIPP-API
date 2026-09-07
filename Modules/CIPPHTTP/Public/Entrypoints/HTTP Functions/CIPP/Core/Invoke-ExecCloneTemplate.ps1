function Invoke-ExecCloneTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.ReadWrite
    #>
    param(
        $Request,
        $TriggerMetadata
    )

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $GUID = $Request.Query.GUID ?? $Request.Body.GUID
    $Type = $Request.Query.Type ?? $Request.Body.Type

    if ($GUID -and $Type) {
        $Table = Get-CIPPTable -tablename templates
        $SafeType = ConvertTo-CIPPODataFilterValue -Value $Type -Type String
        $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type String
        $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeType' and RowKey eq '$SafeGUID'"

        if ($Template) {
            $NewGuid = [guid]::NewGuid().ToString()
            $Template.RowKey = $NewGuid
            $Template.JSON = $Template.JSON -replace $GUID, $NewGuid
            if ($Template.Package) {
                $Template.Package = $null
            }
            if ($Template.SHA) {
                $Template.SHA = $null
            }
            try {
                Add-CIPPAzDataTableEntity @Table -Entity $Template
                $Result = "Template cloned successfully (Type=$Type, NewGuid=$NewGuid)"
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Info'
                $body = @{
                    Results = @{
                        state      = 'success'
                        resultText = 'Template cloned successfully'
                    }
                }
            } catch {
                $ErrorMessage = Get-CIPPException -Exception $_
                $Result = "Failed to clone template (Type=$Type, GUID=$GUID): $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Error' -LogData $ErrorMessage
                $body = @{
                    Results = @{
                        state      = 'error'
                        resultText = 'Failed to clone template'
                        details    = $ErrorMessage
                    }
                }
            }
        } else {
            $body = @{
                Results = @{
                    state      = 'error'
                    resultText = 'Template not found'
                }
            }
        }
    } else {
        $body = @{
            Results = @{
                state      = 'error'
                resultText = 'GUID or Type not provided'
            }
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
