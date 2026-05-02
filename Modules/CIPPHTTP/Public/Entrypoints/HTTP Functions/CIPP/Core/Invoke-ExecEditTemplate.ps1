function Invoke-ExecEditTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Table = Get-CippTable -tablename 'templates'
        $guid = $request.Body.id ? $request.Body.id : $request.Body.GUID
        $JSON = ConvertTo-Json -Compress -Depth 100 -InputObject ($request.Body | Select-Object * -ExcludeProperty GUID)
        $Type = $request.Query.Type ?? $Request.Body.Type

        if ($Type -eq 'IntuneTemplate') {
            Write-Host 'Intune Template'
            $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type String
            $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$SafeGUID'"
            $OriginalJSON = $Template.JSON

            $TemplateData = $Template.JSON | ConvertFrom-Json
            $TemplateType = $TemplateData.Type

            if ($Template.SHA) {
                $NewGuid = [guid]::NewGuid().ToString()
            } else {
                $NewGuid = $GUID
            }
            if ($Request.Body.parsedRAWJson) {
                $RawJSON = ConvertTo-Json -Compress -Depth 100 -InputObject $Request.Body.parsedRAWJson
            } else {
                $RawJSON = $TemplateData.RAWJson
            }

            # Extract display name — different policy types use different fields inside RAWJson
            $ParsedRaw = $RawJSON | ConvertFrom-Json -ErrorAction SilentlyContinue
            $DisplayName = $Request.Body.displayName ?? $ParsedRaw.displayName ?? $ParsedRaw.name ?? $TemplateData.Displayname

            # Sync the resolved display name back into the RAWJson so it stays consistent
            if ($ParsedRaw -and $DisplayName) {
                # Property casing varies by policy type (displayName vs name)
                $rawProps = $ParsedRaw.PSObject.Properties.Name
                if ($rawProps -contains 'displayName') {
                    $ParsedRaw.displayName = $DisplayName
                }
                if ($rawProps -contains 'name') {
                    $ParsedRaw.name = $DisplayName
                }
                $RawJSON = ConvertTo-Json -Compress -Depth 100 -InputObject $ParsedRaw
            }

            $IntuneTemplate = @{
                GUID         = $NewGuid
                RawJson      = $RawJSON
                DisplayName  = $DisplayName
                Description  = $Request.Body.description ?? $TemplateData.Description
                templateType = $TemplateType
                Package      = $Template.Package
                Headers      = $Request.Headers
            }
            Set-CIPPIntuneTemplate @IntuneTemplate
        } else {
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$JSON"
                RowKey       = "$GUID"
                PartitionKey = "$Type"
                GUID         = "$GUID"
            }
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Edited template $($Request.Body.name) with GUID $GUID" -Sev 'Debug'
        }
        $body = [pscustomobject]@{ 'Results' = 'Successfully saved the template' }

    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed to edit template: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Editing template failed: $($_.Exception.Message)" }
    }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
