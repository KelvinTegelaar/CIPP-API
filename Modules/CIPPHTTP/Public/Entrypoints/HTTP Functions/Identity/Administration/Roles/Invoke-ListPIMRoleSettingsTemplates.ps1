function Invoke-ListPIMRoleSettingsTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Role.Read
    .SYNOPSIS
        List PIM role settings templates.
    .DESCRIPTION
        Lists saved Privileged Identity Management role settings templates. A template names a set of roles and the activation, eligibility, assignment, approval and notification rules to enforce on them; the PIMRoleSettings standard deploys a template to tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # Return only the template with this GUID.
    $GUID = $Request.Query.GUID ?? $Request.Query.id

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'PIMRoleSettingsTemplate'"
    if (-not [string]::IsNullOrWhiteSpace($GUID)) {
        $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type String
        $Filter = "$Filter and RowKey eq '$SafeGUID'"
    }

    $Templates = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter | ForEach-Object {
            $Row = $_
            try {
                $Data = $Row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                $Data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $Row.GUID -Force
                $Data | Add-Member -NotePropertyName 'RowKey' -NotePropertyValue $Row.RowKey -Force
                # Grade the stored settings so the list shows a template that has drifted below
                # the floor (e.g. edited in the table) before it is deployed.
                $Floor = Test-CIPPPIMRoleSettingsFloor -Settings (ConvertTo-CIPPPIMRoleSettings -InputObject $Data.settings)
                $Data | Add-Member -NotePropertyName 'meetsSecureFloor' -NotePropertyValue $Floor.Valid -Force
                $Data | Add-Member -NotePropertyName 'floorIssues' -NotePropertyValue @($Floor.Errors) -Force
                $Data | Add-Member -NotePropertyName 'roleCount' -NotePropertyValue (@($Data.roles).Count) -Force
                $Data
            } catch {
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to read PIM role settings template $($Row.RowKey): $($_.Exception.Message)" -sev 'Warning'
            }
        } | Sort-Object -Property templateName)

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Templates)
    }
}
