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
    $StatusCode = [HttpStatusCode]::OK
    $Type = $Request.Query.Type ?? $Request.Body.Type
    if ($Type -notin 'IntuneTemplate', 'CATemplate') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [pscustomobject]@{ Results = 'Type must be IntuneTemplate or CATemplate.' }
            })
    }
    # Canonical casing: the type is also the table partition, which is case-sensitive.
    $Type = if ($Type -eq 'IntuneTemplate') { 'IntuneTemplate' } else { 'CATemplate' }
    $guid = $request.Body.id ? $request.Body.id : $request.Body.GUID
    $TypePermission = @{ CATemplate = 'Tenant.ConditionalAccess.ReadWrite'; IntuneTemplate = 'Endpoint.MEM.ReadWrite' }[$Type]
    if (-not (Test-CippTemplateWriteAccess -Permission $TypePermission -PartitionKey $Type -RowKey $guid)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = "Changing this template needs $TypePermission and a role that is not limited to specific tenants." } })
    }
    try {
        $Table = Get-CippTable -tablename 'templates'
        $JSON = ConvertTo-Json -Compress -Depth 100 -InputObject ($request.Body | Select-Object * -ExcludeProperty GUID, source, isSynced, package)

        if ($Type -eq 'IntuneTemplate') {
            Write-Information 'Intune Template'
            $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type String
            $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$SafeGUID'"
            $OriginalJSON = $Template.JSON

            $TemplateData = $Template.JSON | ConvertFrom-Json
            $TemplateType = $TemplateData.Type

            # A synced template is forked so the sync keeps its own copy. A manual catalog import
            # is edited in place and keeps its repo link, so the catalog still recognises it.
            $IsManualImport = $Template.ManualImport -eq $true
            if ($Template.SHA -and -not $IsManualImport) {
                $NewGuid = [guid]::NewGuid().ToString()
            } else {
                $NewGuid = $GUID
            }
            $PayloadChanged = [bool]$Request.Body.parsedRAWJson
            if ($PayloadChanged) {
                # Not every type requires @odata.type, so losing it is only definitely wrong when the
                # stored policy had one. Set-CIPPIntuneTemplate validates the rest.
                $Incoming = $Request.Body.parsedRAWJson
                $Stored = $TemplateData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue

                if ($Stored.'@odata.type' -and -not $Incoming.'@odata.type') {
                    throw [System.ArgumentException]::new("The submitted policy is missing its '@odata.type' and was not saved, because it would no longer deploy.")
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
                GUID           = $NewGuid
                RawJson        = $RawJSON
                DisplayName    = $DisplayName
                Description    = $Request.Body.description ?? $TemplateData.Description
                templateType   = $TemplateType
                Package        = $Template.Package
                Headers        = $Request.Headers
                PayloadChanged = $PayloadChanged
            }
            # The row is rebuilt from scratch, so carry the reusable-setting references across
            if ($TemplateData.ReusableSettings) { $IntuneTemplate.ReusableSettings = $TemplateData.ReusableSettings }
            if ($IsManualImport) {
                $IntuneTemplate.Metadata = @{ SHA = $Template.SHA; Source = $Template.Source; SourcePath = $Template.SourcePath; ManualImport = $true }
            }
            Set-CIPPIntuneTemplate @IntuneTemplate
        } else {
            $Entity = @{
                JSON         = "$JSON"
                RowKey       = "$GUID"
                PartitionKey = "$Type"
                GUID         = "$GUID"
            }
            # Editing detaches a synced template from its library. A manual catalog import keeps its SHA.
            $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type String
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate' and RowKey eq '$SafeGUID'"
            if ($Existing.ManualImport -ne $true) { $Entity.SHA = '' }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -OperationType 'UpsertMerge'
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant 'Global' -message "Edited template $($Request.Body.name) with GUID $GUID" -Sev 'Info'
        }
        $body = [pscustomobject]@{ 'Results' = 'Successfully saved the template' }

    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant 'Global' -message "Failed to edit template: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Editing template failed: $($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
