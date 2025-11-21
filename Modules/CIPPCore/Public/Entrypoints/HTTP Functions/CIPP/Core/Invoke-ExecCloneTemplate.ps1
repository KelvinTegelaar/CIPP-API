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

    $GUID = $Request.Query.GUID ?? $Request.Body.GUID
    $Type = $Request.Query.Type ?? $Request.Body.Type

    if ($GUID -and $Type) {
        $Table = Get-CIPPTable -tablename templates
        $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$Type' and RowKey eq '$GUID'"

        if ($Template) {
            $NewGuid = [guid]::NewGuid().ToString()
            $Template.RowKey = $NewGuid
            $Template.JSON = $Template.JSON -replace $GUID, $NewGuid
            $Template.Package = $null
            $Template.SHA = $null
            try {
                Add-CIPPAzDataTableEntity @Table -Entity $Template
                $body = @{
                    Results = @{
                        state      = 'success'
                        resultText = 'Template cloned successfully'
                    }
                }
            } catch {
                $body = @{
                    Results = @{
                        state      = 'error'
                        resultText = 'Failed to clone template'
                        details    = Get-CIPPException -Exception $_
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
