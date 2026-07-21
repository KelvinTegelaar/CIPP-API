function Invoke-ListSharePointTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Sharepoint.Admin.Read
    .DESCRIPTION
        Lists saved SharePoint provisioning templates (site templates and their document libraries).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Table = Get-CIPPTable -TableName 'templates'

    try {
        $Filter = "PartitionKey eq 'SharePointTemplate'"
        $Templates = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        $Body = $Templates | ForEach-Object {
            try {
                $TemplateData = $null
                if ($_.JSON) {
                    $TemplateData = $_.JSON | ConvertFrom-Json -ErrorAction Stop
                }

                $TemplateObject = [PSCustomObject]@{
                    TemplateId = $_.RowKey
                    Timestamp  = $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                }

                if ($TemplateData) {
                    foreach ($Property in $TemplateData.PSObject.Properties) {
                        $TemplateObject | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value -Force
                    }
                }

                # Surface scalar counts so the list can show/sort them without inspecting the nested arrays.
                $SiteTemplates = @($TemplateData.siteTemplates | Where-Object { $_ })
                $LibraryCount = ($SiteTemplates | ForEach-Object { @($_.libraries | Where-Object { $_ }).Count } | Measure-Object -Sum).Sum
                $TemplateObject | Add-Member -NotePropertyName 'SiteTemplateCount' -NotePropertyValue ([int]$SiteTemplates.Count) -Force
                $TemplateObject | Add-Member -NotePropertyName 'LibraryCount' -NotePropertyValue ([int]$LibraryCount) -Force

                return $TemplateObject
            } catch {
                Write-LogMessage -headers $Headers -API $APIName -message "Error processing SharePoint template $($_.RowKey): $($_.Exception.Message)" -Sev 'Error'
                return [PSCustomObject]@{
                    TemplateId   = $_.RowKey
                    templateName = 'Error parsing template data'
                    Error        = $_.Exception.Message
                    Timestamp    = $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
            }
        }
    } catch {
        $Body = @{
            Results = "Failed to list SharePoint templates: $($_.Exception.Message)"
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject @($Body)
        })
}
