using namespace System.Net

Function Invoke-ExecMaintenanceScripts {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    try {
        $GraphToken = Get-GraphToken -returnRefresh $true
        $AccessTokenDetails = Read-JwtAccessDetails -Token $GraphToken.access_token

        $ReplacementStrings = @{
            '##TENANTID##'      = $env:TenantID
            '##RESOURCEGROUP##' = $env:WEBSITE_RESOURCE_GROUP
            '##FUNCTIONAPP##'   = $env:WEBSITE_SITE_NAME 
            '##SUBSCRIPTION##'  = (($env:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1)
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
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to retrieve maintenance scripts. Error: $($_.Exception.Message)" -Sev 'Error'
        $Body = @{Status = "Failed to retrieve maintenance scripts $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
