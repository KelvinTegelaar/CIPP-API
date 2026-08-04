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
        $JSON = ConvertTo-Json -Compress -Depth 100 -InputObject ($request.Body | Select-Object * -ExcludeProperty GUID, source, isSynced, package)
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
                # Intune identifies a policy and every setting in it by @odata.type, and rejects a
                # policy that is missing them. An editor that rebuilds the body from form state can
                # drop them silently, which stores a template that only fails at deployment time -
                # so refuse the write here rather than let a working template be replaced by one
                # that cannot deploy.
                $Incoming = $Request.Body.parsedRAWJson
                $Stored = $TemplateData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue

                if ($Stored.'@odata.type' -and -not $Incoming.'@odata.type') {
                    throw "The submitted policy is missing its '@odata.type' and was not saved, because it would no longer deploy."
                }

                $MissingType = @($Incoming.settings).Where({ $_.settingInstance -and -not $_.settingInstance.'@odata.type' })
                if ($MissingType.Count -gt 0) {
                    throw "The submitted policy has $($MissingType.Count) setting(s) missing '@odata.type' and was not saved, because it would no longer deploy."
                }

                $RawJSON = ConvertTo-Json -Compress -Depth 100 -InputObject $Incoming
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
            $Entity = @{
                JSON         = "$JSON"
                RowKey       = "$GUID"
                PartitionKey = "$Type"
                GUID         = "$GUID"
                SHA          = ''
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -OperationType 'UpsertMerge'
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
