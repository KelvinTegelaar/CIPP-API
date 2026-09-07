Function Invoke-ExecMaintenanceScripts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    .DESCRIPTION
        Returns the maintenance scripts shipped with CIPP. Called without ScriptFile it lists the available scripts; with one it returns that script with the deployment's own tenant, subscription and resource details substituted in. MakeLink stores the result behind a one-time link instead.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $GraphToken = Get-GraphToken -returnRefresh $true
        $AccessTokenDetails = Read-JwtAccessDetails -Token $GraphToken.access_token

        $ReplacementStrings = @{
            '##TENANTID##'      = $env:TenantID
            '##RESOURCEGROUP##' = $env:WEBSITE_RESOURCE_GROUP
            '##FUNCTIONAPP##'   = $env:WEBSITE_SITE_NAME
            '##SUBSCRIPTION##'  = Get-CIPPAzFunctionAppSubId
            '##TOKENIP##'       = $AccessTokenDetails.IPAddress
        }
    } catch { Write-Host $_.Exception.Message }
    #$ReplacementStrings | Format-Table

    try {
        $ScriptFile = $Request.Query.ScriptFile

        try {
            $Filename = Split-Path -Leaf $ScriptFile
        } catch {}

        if (!$ScriptFile -or [string]::IsNullOrEmpty($ScriptFile)) {
            $ScriptFiles = Get-ChildItem (Join-Path $env:CIPPRootPath 'ExecMaintenanceScripts\Scripts') | Select-Object -ExpandProperty PSChildName

            $ScriptOptions = foreach ($ScriptFile in $ScriptFiles) {
                @{label = $ScriptFile; value = $ScriptFile }
            }
            $Body = @{ ScriptFiles = @($ScriptOptions) }
        } elseif (!(Get-ChildItem (Join-Path $env:CIPPRootPath "ExecMaintenanceScripts\Scripts\$Filename") -ErrorAction SilentlyContinue)) {
            $Body = @{ Status = 'Script does not exist' }
        } else {
            $Script = Get-Content -Raw (Join-Path $env:CIPPRootPath "ExecMaintenanceScripts\Scripts\$Filename")
            foreach ($i in $ReplacementStrings.Keys) {
                $Script = $Script -replace $i, $ReplacementStrings.$i
            }

            $ScriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))

            if ($Request.Query.MakeLink) {
                $Table = Get-CippTable -TableName 'MaintenanceScripts'
                $LinkGuid = ([guid]::NewGuid()).ToString()

                $MaintenanceScriptRow = @{
                    'RowKey'        = $LinkGuid
                    'PartitionKey'  = 'Maintenance'
                    'ScriptContent' = $ScriptContent
                }
                Add-CIPPAzDataTableEntity @Table -Entity $MaintenanceScriptRow -Force

                Write-LogMessage -headers $Request.Headers -API $APIName -tenant 'Global' -message "Created one-time maintenance script link for $Filename" -Sev 'Info'
                $Body = @{ Link = "/api/PublicScripts?guid=$LinkGuid" }
            } else {
                $Body = @{ ScriptContent = $ScriptContent }
            }
        }
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($tenantfilter) -message "Failed to retrieve maintenance scripts. Error: $($_.Exception.Message)" -Sev 'Error'
        $Body = @{Status = "Failed to retrieve maintenance scripts $($_.Exception.Message)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
