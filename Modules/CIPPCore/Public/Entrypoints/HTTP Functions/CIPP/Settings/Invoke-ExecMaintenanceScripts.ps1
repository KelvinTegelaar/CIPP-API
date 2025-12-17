Function Invoke-ExecMaintenanceScripts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
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
            $ScriptFiles = Get-ChildItem .\ExecMaintenanceScripts\Scripts | Select-Object -ExpandProperty PSChildName

            $ScriptOptions = foreach ($ScriptFile in $ScriptFiles) {
                @{label = $ScriptFile; value = $ScriptFile }
            }
            $Body = @{ ScriptFiles = @($ScriptOptions) }
        } elseif (!(Get-ChildItem .\ExecMaintenanceScripts\Scripts\$Filename -ErrorAction SilentlyContinue)) {
            $Body = @{ Status = 'Script does not exist' }
        } else {
            $Script = Get-Content -Raw .\ExecMaintenanceScripts\Scripts\$Filename
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
