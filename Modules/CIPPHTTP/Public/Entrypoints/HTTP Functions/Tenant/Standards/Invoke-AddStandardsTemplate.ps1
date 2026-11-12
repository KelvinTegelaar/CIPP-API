function Invoke-AddStandardsTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    if ($Request.Body.tenantFilter -eq 'tenantFilter') {
        throw 'Invalid Tenant Selection. A standard must be assigned to at least 1 tenant.'
    }

    # tenantFilter is a selector list the dispatcher does not check, and standards runs never re-check
    # access, so check every target here by its value; an edit must also cover the row it replaces.
    # 'Template Tenant' is the repo-import placeholder and targets nothing.
    $GUID = $Request.body.GUID ? $request.body.GUID : (New-Guid).GUID
    $Table = Get-CippTable -tablename 'templates'
    $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type String
    $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$SafeGUID'"
    try {
        $Targets = @($Request.Body.tenantFilter; if ($Existing.JSON) { ($Existing.JSON | ConvertFrom-Json).tenantFilter })
        Assert-CippTenantAccess -Request $Request -TenantFilter @($Targets | Where-Object { "$($_.value ?? $_)" -ne 'Template Tenant' })
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Blocked standards template save: $($_.Exception.Message)" -Sev 'Warning'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = $_.Exception.Message
            })
    }

    # Optional. Pushes the saved template to a GitHub template repository after the save: FullName is
    # the repository (owner/repo), Message is the commit message. Not stored on the template.
    $GitHubPush = $Request.body.GitHub
    if ($Request.body.PSObject.Properties.Name -contains 'GitHub') {
        $Request.body.PSObject.Properties.Remove('GitHub')
    }

    #updatedBy    = $request.headers.'x-ms-client-principal'
    #updatedAt    = (Get-Date).ToUniversalTime()
    $request.body | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
    $request.body | Add-Member -NotePropertyName 'createdAt' -NotePropertyValue ($Request.body.createdAt ? $Request.body.createdAt : (Get-Date).ToUniversalTime()) -Force
    $Request.body | Add-Member -NotePropertyName 'updatedBy' -NotePropertyValue ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails -Force
    $Request.body | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-Date).ToUniversalTime() -Force

    # Drop standards toggled on but left with no instances (empty array) - e.g. a template standard
    # whose last selection was removed in the editor, which leaves 'standards.<Name> = []' in the form.
    # Persisting these produces phantom 'NOT FOUND' drift entries with no template to compare against.
    if ($Request.body.standards) {
        foreach ($Property in @($Request.body.standards.PSObject.Properties)) {
            if ($Property.Value -is [array] -and $Property.Value.Count -eq 0) {
                $Request.body.standards.PSObject.Properties.Remove($Property.Name)
            }
        }
    }

    $JSON = (ConvertTo-Json -Compress -Depth 100 -InputObject ($Request.body))
    $Entity = @{
        JSON         = "$JSON"
        RowKey       = "$GUID"
        PartitionKey = 'StandardsTemplateV2'
        GUID         = "$GUID"
    }
    # This write replaces the row. A template imported from a template repo carries SHA and Source,
    # which the repo sync uses to skip files that have not changed; dropping them makes the next sync
    # treat the row as new and overwrite the edits made here with the repo copy.
    if ($Existing.SHA) { $Entity.SHA = $Existing.SHA }
    if ($Existing.Source) { $Entity.Source = $Existing.Source }
    if ($Existing.SourcePath) { $Entity.SourcePath = $Existing.SourcePath }
    if ($Existing.ContentHash) { $Entity.ContentHash = $Existing.ContentHash }
    $Table.Force = $true
    Add-CIPPAzDataTableEntity @Table -Entity $Entity

    $AddObject = @{
        PartitionKey = 'InstanceProperties'
        RowKey       = 'CIPPURL'
        Value        = [string]([System.Uri]$Headers.'x-ms-original-url').Host
    }
    $ConfigTable = Get-CIPPTable -tablename 'Config'
    Add-AzDataTableEntity @ConfigTable -Entity $AddObject -Force

    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Standards Template $($Request.body.templateName) with GUID $GUID added/edited." -Sev 'Info'

    $ResultsMessage = 'Successfully added template'
    if ($GitHubPush.FullName) {
        try {
            $PushResult = Push-CIPPTemplateToRepo -GUID $GUID -FullName $GitHubPush.FullName -Message $GitHubPush.Message
            if ($PushResult.state -eq 'success') {
                $ResultsMessage = "$ResultsMessage. Pushed to $($GitHubPush.FullName)."
            } else {
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to push template $GUID to $($GitHubPush.FullName): $($PushResult.resultText)" -Sev 'Error'
                $ResultsMessage = "$ResultsMessage. Failed to push to $($GitHubPush.FullName): $($PushResult.resultText)"
            }
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to push template $GUID to $($GitHubPush.FullName): $($_.Exception.Message)" -Sev 'Error'
            $ResultsMessage = "$ResultsMessage. Failed to push to $($GitHubPush.FullName): $($_.Exception.Message)"
        }
    }
    $body = [pscustomobject]@{'Results' = $ResultsMessage; Metadata = @{id = $GUID } }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
