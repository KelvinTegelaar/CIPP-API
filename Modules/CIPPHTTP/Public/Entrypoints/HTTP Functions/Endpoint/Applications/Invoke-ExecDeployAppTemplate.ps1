function Invoke-ExecDeployAppTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TemplateId = $Request.Body.templateId
        if (!$TemplateId) { throw 'No template ID provided' }

        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'AppTemplate' and RowKey eq '$TemplateId'"
        $TemplateEntity = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if (!$TemplateEntity) { throw 'Template not found' }

        $TemplateData = $TemplateEntity.JSON | ConvertFrom-Json -Depth 100
        $AppsRaw = $TemplateData.Apps

        $Apps = [System.Collections.Generic.List[PSCustomObject]]::new()

        $AppTypes = @($AppsRaw.appType)
        $AppNames = @($AppsRaw.appName)
        $AppConfigs = @($AppsRaw.config)

        for ($i = 0; $i -lt $AppTypes.Count; $i++) {
            $Apps.Add([PSCustomObject]@{
                appType = [string]$AppTypes[$i]
                appName = [string]$AppNames[$i]
                config  = [string]$AppConfigs[$i]
            })
        }

        $SelectedTenants = @($Request.Body.selectedTenants | ForEach-Object {
            [PSCustomObject]@{
                defaultDomainName = $_.defaultDomainName
                customerId        = $_.customerId
            }
        })

        $OverrideAssignTo = $Request.Body.AssignTo
        $OverrideCustomGroup = $Request.Body.customGroup

        $Results = foreach ($App in $Apps) {
            try {
                $Config = $App.config
                if ($Config -is [string]) {
                    $Config = $Config | ConvertFrom-Json -Depth 100
                }

                $AppType = "$($App.appType ?? $App.AppType)"

                $RequestBody = $Config | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
                $RequestBody | Add-Member -NotePropertyName 'selectedTenants' -NotePropertyValue $SelectedTenants -Force
                $RequestBody | Add-Member -NotePropertyName 'tenantFilter' -NotePropertyValue 'allTenants' -Force

                if ($OverrideAssignTo) {
                    $RequestBody | Add-Member -NotePropertyName 'AssignTo' -NotePropertyValue $OverrideAssignTo -Force
                    if ($OverrideAssignTo -eq 'customGroup' -and $OverrideCustomGroup) {
                        $RequestBody | Add-Member -NotePropertyName 'CustomGroup' -NotePropertyValue $OverrideCustomGroup -Force
                    }
                }

                $MockRequest = [PSCustomObject]@{
                    Body    = $RequestBody
                    Headers = $Headers
                    Params  = @{ CIPPEndpoint = $APIName }
                    Query   = @{}
                }

                $HandlerResult = switch ($AppType) {
                    'StoreApp'       { Invoke-AddStoreApp -Request $MockRequest -TriggerMetadata $null }
                    'chocolateyApp'  { Invoke-AddChocoApp -Request $MockRequest -TriggerMetadata $null }
                    'officeApp'      { Invoke-AddOfficeApp -Request $MockRequest -TriggerMetadata $null }
                    'win32ScriptApp' { Invoke-AddWin32ScriptApp -Request $MockRequest -TriggerMetadata $null }
                    'mspApp'         { Invoke-AddMSPApp -Request $MockRequest -TriggerMetadata $null }
                    default          { throw "Unknown app type: $AppType" }
                }

                if ($HandlerResult.Body.Results) {
                    $HandlerResult.Body.Results
                } elseif ($HandlerResult.Body) {
                    $HandlerResult.Body
                } else {
                    "Queued '$($App.appName)'"
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                "Failed '$($App.appName)': $($ErrorMessage.NormalizedMessage)"
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to deploy app '$($App.appName)' from template: $($ErrorMessage.NormalizedMessage)" -Sev 'Error' -LogData $ErrorMessage
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to deploy app template: $($ErrorMessage.NormalizedMessage)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    })
}
