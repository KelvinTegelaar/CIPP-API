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
                    $Config = $Config | ConvertFrom-CippAppConfig
                }

                $AppType = "$($App.appType ?? $App.AppType)"

                $RequestBody = $Config | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
                $RequestProps = [ordered]@{
                    selectedTenants = $SelectedTenants
                    tenantFilter    = 'allTenants'
                }
                if ($OverrideAssignTo) {
                    $RequestProps['AssignTo'] = $OverrideAssignTo
                    if ($OverrideAssignTo -eq 'customGroup' -and $OverrideCustomGroup) {
                        $RequestProps['CustomGroup'] = $OverrideCustomGroup
                    }
                }
                $RequestBody | Add-Member -NotePropertyMembers $RequestProps -Force

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
                    'edgeApp'        { Invoke-AddEdgeApp -Request $MockRequest -TriggerMetadata $null }
                    default          { throw "Unknown app type: $AppType" }
                }

                $DeployedResult = if ($HandlerResult.Body.Results) {
                    $HandlerResult.Body.Results
                } elseif ($HandlerResult.Body) {
                    $HandlerResult.Body
                } else {
                    "Queued '$($App.appName)'"
                }

                # Handlers signal rejection by status code, not by throwing.
                $HandlerStatus = [int]$HandlerResult.StatusCode
                if ($HandlerStatus -ge 200 -and $HandlerStatus -lt 300) {
                    Write-LogMessage -headers $Headers -API $APIName -message "Deployed app '$($App.appName)' ($AppType) from template $TemplateId" -Sev 'Info'
                    $DeployedResult
                } else {
                    $FailureText = "Failed to deploy app '$($App.appName)' ($AppType) from template $($TemplateId): $($DeployedResult -join '; ')"
                    Write-LogMessage -headers $Headers -API $APIName -message $FailureText -Sev 'Error'
                    $FailureText
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                "Failed '$($App.appName)': $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to deploy app '$($App.appName)' from template: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to deploy app template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    })
}
