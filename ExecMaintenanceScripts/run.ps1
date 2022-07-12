using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata) 

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

try {
    $ReplacementStrings = @{
        '##TENANTID##'      = $ENV:TenantId
        '##RESOURCEGROUP##' = $ENV:WEBSITE_RESOURCE_GROUP
        '##FUNCTIONAPP##'   = $ENV:WEBSITE_SITE_NAME 
        '##SUBSCRIPTION##'  = (($ENV:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1)
    }
}
catch { Write-Host $_.Exception.Message }
$ReplacementStrings | Format-Table

try {
    $ScriptFile = $Request.Query.ScriptFile

    try {
        $Filename = Split-Path -Leaf $ScriptFile
    }
    catch {}

    if (!$ScriptFile -or [string]::IsNullOrEmpty($ScriptFile)) {
        $ScriptFiles = Get-ChildItem .\ExecMaintenanceScripts\Scripts | Select-Object -ExpandProperty PSChildName

        $ScriptOptions = foreach ($ScriptFile in $ScriptFiles) {
            @{label = $ScriptFile; value = $ScriptFile }
        }
        $Body = @{ ScriptFiles = @($ScriptOptions) }
    }
    elseif (!(Get-ChildItem .\ExecMaintenanceScripts\Scripts\$Filename -ErrorAction SilentlyContinue)) {
        $Body = @{ Status = 'Script does not exist' }
    }
    else {
        $Script = Get-Content -Raw .\ExecMaintenanceScripts\Scripts\$Filename
        foreach ($i in $ReplacementStrings.Keys) {
            $Script = $Script -replace $i, $ReplacementStrings.$i
        }

        $ScriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))

        if ($Request.Query.MakeLink) {
            $Table = Get-CippTable -TableName 'MaintenanceScripts'
            $LinkGuid = (New-Guid).Guid

            $MaintenanceScriptRow = @{
                'Table'        = $Table
                'rowKey'       = $LinkGuid
                'partitionKey' = 'Maintenance'
                'property'     = @{
                    'ScriptContent' = $ScriptContent
                }
            }
            Add-AzTableRow @MaintenanceScriptRow

            $Body = @{ Link = "/api/PublicScripts?guid=$LinkGuid" }
        }
        else {
            $Body = @{ ScriptContent = $ScriptContent }
        }
    }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to retrieve maintenance scripts. Error: $($_.Exception.Message)" -Sev 'Error'
    $Body = @{Status = "Failed to retrieve maintenance scripts $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
