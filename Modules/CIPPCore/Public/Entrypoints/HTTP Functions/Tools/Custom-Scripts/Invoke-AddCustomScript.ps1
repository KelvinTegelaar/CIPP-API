function Invoke-AddCustomScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.CustomScript.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Headers = $Request.Headers

    try {
        $RestoreToVersion = $Request.Body.RestoreToVersion
        $ScriptGuid = $Request.Body.ScriptGuid

        if ($RestoreToVersion) {
            if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
                throw 'ScriptGuid is required for restore operation'
            }

            $Table = Get-CippTable -tablename 'CustomPowershellScripts'
            $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
            $ExistingScripts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            $TargetScript = $ExistingScripts | Where-Object { $_.Version -eq $RestoreToVersion }
            if (-not $TargetScript) {
                throw "Version $RestoreToVersion not found for script GUID '$ScriptGuid'"
            }

            $NewerVersions = $ExistingScripts | Where-Object { $_.Version -gt $RestoreToVersion }
            foreach ($script in $NewerVersions) {
                Remove-AzDataTableEntity @Table -Entity $script
            }

            Write-LogMessage -API $APIName -headers $Headers -message "Restored custom script: $($TargetScript.ScriptName) to version $RestoreToVersion (Deleted $($NewerVersions.Count) newer version(s))" -sev 'Info'

            $Body = @{
                Results = "Successfully restored custom script '$($TargetScript.ScriptName)' to version $RestoreToVersion"
            }

            $StatusCode = [HttpStatusCode]::OK
        } else {
            $ScriptName = $Request.Body.ScriptName
            $ScriptContent = $Request.Body.ScriptContent
            $Description = $Request.Body.Description
            $Category = $Request.Body.Category
            $Risk = $Request.Body.Risk
            $Pillar = $Request.Body.Pillar
            $ImplementationEffort = $Request.Body.ImplementationEffort
            $UserImpact = $Request.Body.UserImpact
            $Enabled = $Request.Body.Enabled
            $AlertOnFailure = $Request.Body.AlertOnFailure
            $ReturnType = $Request.Body.ReturnType
            $MarkdownTemplate = $Request.Body.MarkdownTemplate
            $ResultSchema = $Request.Body.ResultSchema

            if ([string]::IsNullOrWhiteSpace($ReturnType)) {
                $ReturnType = 'JSON'
            }

            if ([string]::IsNullOrWhiteSpace($ScriptName)) {
                throw 'ScriptName is required'
            }

            if ([string]::IsNullOrWhiteSpace($Pillar)) {
                throw 'Pillar is required'
            }

            if ([string]::IsNullOrWhiteSpace($UserImpact)) {
                throw 'UserImpact is required'
            }

            if ([string]::IsNullOrWhiteSpace($ImplementationEffort)) {
                throw 'ImplementationEffort is required'
            }

            $ValidReturnTypes = @('JSON', 'Markdown')
            if ($ReturnType -notin $ValidReturnTypes) {
                throw "ReturnType must be one of: $($ValidReturnTypes -join ', ')"
            }

            $ValidPillars = @('Identity', 'Devices', 'Data')
            if ($Pillar -notin $ValidPillars) {
                throw "Pillar must be one of: $($ValidPillars -join ', ')"
            }

            $ValidImpactAndEffort = @('Low', 'Medium', 'High')
            if ($UserImpact -notin $ValidImpactAndEffort) {
                throw "UserImpact must be one of: $($ValidImpactAndEffort -join ', ')"
            }

            if ($ImplementationEffort -notin $ValidImpactAndEffort) {
                throw "ImplementationEffort must be one of: $($ValidImpactAndEffort -join ', ')"
            }

            if ($ScriptName -notmatch '^[a-zA-Z0-9\s\-_]+$') {
                throw 'ScriptName can only contain letters, numbers, spaces, hyphens, and underscores. Spaces are allowed but may affect command-line usage.'
            }

            $Table = Get-CippTable -tablename 'CustomPowershellScripts'

            if ($ScriptGuid) {
                $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
                $ExistingVersions = Get-CIPPAzDataTableEntity @Table -Filter $Filter
                if (-not $ExistingVersions) {
                    throw "Script with GUID '$ScriptGuid' not found"
                }

                if ([string]::IsNullOrWhiteSpace($ScriptContent)) {
                    $LatestExistingVersion = $ExistingVersions | Sort-Object -Property Version -Descending | Select-Object -First 1
                    $ScriptContent = $LatestExistingVersion.ScriptContent
                }

                if ([string]::IsNullOrWhiteSpace($ResultSchema)) {
                    $ResultSchema = $LatestExistingVersion.ResultSchema ?? ''
                }

                $Version = ($ExistingVersions | Measure-Object -Property Version -Maximum).Maximum + 1
            } else {
                $ScriptGuid = (New-Guid).ToString()
                $Version = 1
            }

            if ([string]::IsNullOrWhiteSpace($ScriptContent)) {
                throw 'ScriptContent is required'
            }

            if ([string]::IsNullOrWhiteSpace($ResultSchema)) {
                $ResultSchema = ''
            }

            Test-CustomScriptSecurity -ScriptContent $ScriptContent

            $RowKey = '{0}-v{1}' -f $ScriptGuid, $Version
            $Entity = @{
                PartitionKey         = 'CustomScript'
                RowKey               = $RowKey
                ScriptGuid           = $ScriptGuid
                ScriptName           = $ScriptName
                Version              = $Version
                ScriptContent        = $ScriptContent
                Description          = $Description
                Category             = $Category
                Risk                 = $Risk
                Pillar               = $Pillar
                ImplementationEffort = $ImplementationEffort
                UserImpact           = $UserImpact
                Enabled              = $Enabled
                AlertOnFailure       = $AlertOnFailure
                ReturnType           = $ReturnType
                MarkdownTemplate     = $MarkdownTemplate
                ResultSchema         = $ResultSchema
                CreatedBy            = if ($Headers) { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } else { 'Unknown' }
                CreatedDate          = (Get-Date).ToUniversalTime().ToString('o')
            }

            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

            Write-LogMessage -API $APIName -headers $Headers -message "Created custom script: $ScriptName (Version: $Version)" -sev 'Info'

            $Body = @{
                Results = "Successfully created custom script '$ScriptName'"
            }

            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -headers $Headers -message "Failed to create custom script: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = $Body
        })
}
