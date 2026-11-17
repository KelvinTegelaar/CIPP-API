function Invoke-ExecExtensionsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Request,

        [Parameter(Mandatory = $false)]
        [object]$TriggerMetadata
    )
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Body = [PSCustomObject]$Request.Body
    $NinjaOneSettings = $Body.NinjaOne
    $HaloSettings = $Body.HaloPSA
    $StatusCode = [HttpStatusCode]::OK
    $Results = try {
        $Refusals = [System.Collections.Generic.List[string]]::new()
        $AllowedNinjaHostnames = @(
            'app.ninjarmm.com',
            'eu.ninjarmm.com',
            'oc.ninjarmm.com',
            'ca.ninjarmm.com',
            'us2.ninjarmm.com'
        )
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $StoredConfig = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CippExtensions' and RowKey eq 'Config'").config
        $StoredConfig = if ($StoredConfig) { $StoredConfig | ConvertFrom-Json -Depth 10 } else { $null }

        # An old value on a disabled NinjaOne that nobody is changing must not block saving other integrations.
        $SetNinjaHostname = "$($Body.NinjaOne.Instance)" -replace '/ws', '' -replace 'https://', ''
        $NinjaChecked = $Body.NinjaOne.Enabled -eq $true -or "$($Body.NinjaOne.Instance)".Trim() -ne "$($StoredConfig.NinjaOne.Instance)".Trim()
        if ($SetNinjaHostname -and $NinjaChecked -and $AllowedNinjaHostnames -notcontains $SetNinjaHostname) {
            $Refusals.Add("NinjaOne URL is not allowed. Allowed hostnames are: $($AllowedNinjaHostnames -join ', ').")
        }
        # Which stored secrets each extension sends to its configured address. A stored secret is never reused
        # at a new address or newly sent to one, so either change needs a new key in the same save.
        $SecretRoutes = @(
            @{ Name = 'HaloPSA'; Fields = @('AuthURL', 'ResourceURL'); Url = $true; Secrets = { param($c) 'HaloPSA' } }
            @{ Name = 'Hudu'; Fields = @('BaseUrl'); Url = $true; Secrets = { param($c) 'Hudu'; if ($c.Hudu.CFEnabled -eq $true -and $c.CFZTNA.Enabled -eq $true) { 'CFZTNA' } } }
            @{ Name = 'PWPush'; Fields = @('BaseUrl'); Url = $true; Secrets = { param($c) if ($c.PWPush.UseBearerAuth -eq $true -or $c.PWPush.EmailAddress) { 'PWPush' }; if ($c.PWPush.CFEnabled -eq $true -and $c.CFZTNA.Enabled -eq $true) { 'CFZTNA' } } }
            @{ Name = 'NinjaOne'; Fields = @('Instance'); Secrets = { param($c) 'NinjaOne' } }
            @{ Name = 'Syncro'; Fields = @('Subdomain'); Secrets = { param($c) 'Syncro' } }
            @{ Name = 'ExternalCSP'; Fields = @('TestUrl', 'CatalogUrl', 'SubscriptionsUrl', 'OrderUrl', 'QuantityUrl', 'CancelUrl'); Url = $true; Secrets = { param($c) 'ExternalCSP' } }
        )
        foreach ($Route in $SecretRoutes) {
            # No address means nothing is sent anywhere (PWPush falls back to pwpush.com).
            if (-not ($Route.Fields | Where-Object { "$($Body.($Route.Name).$_)".Trim() })) { continue }
            $Moved = $false
            foreach ($Field in $Route.Fields) {
                $New = "$($Body.($Route.Name).$Field)".Trim()
                if ($New.TrimEnd('/') -eq "$($StoredConfig.($Route.Name).$Field)".Trim().TrimEnd('/')) { continue }
                $Moved = $true
                $Parsed = $null
                if ($Route.Url -and $New -and (-not [uri]::TryCreate($New, [System.UriKind]::Absolute, [ref]$Parsed) -or $Parsed.Scheme -ne 'https' -or $Parsed.UserInfo)) {
                    $Refusals.Add("$($Route.Name) $Field must be an https URL without embedded credentials.")
                }
            }
            # Cloudflare Access only adds headers to the same request, so switching it on needs no new key.
            $OldSecrets = if ($StoredConfig) { @(& $Route.Secrets $StoredConfig) } else { @() }
            foreach ($Secret in @(& $Route.Secrets $Body)) {
                $Key = $Body.$Secret.APIKey
                $Started = $Secret -ne 'CFZTNA' -and $OldSecrets -notcontains $Secret
                if ((-not $Key -or $Key -eq 'SentToKeyVault') -and ($Moved -or $Started)) {
                    $Refusals.Add("The $($Route.Name) settings change where the $Secret API key is sent, so the stored key is not reused. Enter a new $Secret API key to save.")
                }
            }
        }
        if ($Body.ExternalCSP.Enabled -eq $true) {
            # One CSP provider serves purchases at a time; the licence endpoints dispatch on whichever is enabled.
            if ($Body.Sherweb.Enabled -eq $true) {
                $Refusals.Add('Sherweb and External CSP cannot both be enabled. Disable one of them and save again.')
            }
            foreach ($UrlSetting in 'TestUrl', 'CatalogUrl', 'SubscriptionsUrl', 'OrderUrl', 'QuantityUrl', 'CancelUrl') {
                if ("$($Body.ExternalCSP.$UrlSetting)" -notmatch '^https://') {
                    $Refusals.Add("External CSP $UrlSetting must be an https URL.")
                }
            }
        }
        # What this save changes, for the logbook. Key values are never recorded, only that a new one was entered.
        $Changes = [ordered]@{}
        $Shown = { param($Value) if ($null -eq $Value) { '' } elseif ($Value -is [string] -or $Value -is [valuetype]) { "$Value" } else { ConvertTo-Json -InputObject $Value -Compress -Depth 5 } }
        foreach ($Extension in $Body.PSObject.Properties.Name) {
            if ($Body.$Extension -isnot [pscustomobject]) { continue }
            $Fields = @($Body.$Extension.PSObject.Properties.Name; $StoredConfig.$Extension.PSObject.Properties.Name) | Where-Object { $_ -and $_ -notin @('ResetPassword', 'NextSync') } | Select-Object -Unique
            foreach ($Field in $Fields) {
                if ($Field -eq 'APIKey') {
                    if ($Body.$Extension.APIKey -and $Body.$Extension.APIKey -ne 'SentToKeyVault') {
                        $Changes["$Extension.APIKey"] = 'new key entered'
                    }
                    continue
                }
                $Old = & $Shown $StoredConfig.$Extension.$Field
                $New = & $Shown $Body.$Extension.$Field
                # A switch that was never set and is now off has not changed.
                if (($Old -replace '^False$', '') -ne ($New -replace '^False$', '')) {
                    $Changes["$Extension.$Field"] = "$($Old ? $Old : '(empty)') -> $($New ? $New : '(empty)')"
                }
            }
        }
        $ChangeLog = @{}
        # One flat entry per setting, so the logbook shows each change as its own row.
        if ($Changes.Count -gt 0) { $ChangeLog.LogData = $Changes }

        if ($Refusals.Count -gt 0) {
            $Result = $Refusals -join ' '
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Extension configuration not saved: $Result" -Sev 'Warning' @ChangeLog
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ 'Results' = $Result } })
        }

        $ScheduleParameters = @{}
        if ($Body.Hudu.NextSync) {
            #parse unixtime for addedtext
            $Timestamp = [datetime]::UnixEpoch.AddSeconds([int]$Body.Hudu.NextSync).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $ScheduleParameters = @{
                Reschedule = $true
                NextSync   = $Body.Hudu.NextSync
                Extensions = 'Hudu'
            }
            $AddedText = " Next sync will be at $Timestamp."
            $Body.Hudu.NextSync = ''
        }

        # The property name becomes the stored secret's name, so only the extensions the settings form posts may store one.
        $KnownExtensions = @('AutotaskPSA', 'CFZTNA', 'cippapi', 'ConnectWisePSA', 'ExternalCSP', 'GitHub', 'Gradient', 'HaloPSA', 'HIBP', 'Hudu', 'KaseyaBMS', 'NinjaOne', 'Pax8', 'PWPush', 'Sherweb', 'Syncro')
        foreach ($APIKey in $Body.PSObject.Properties.Name) {
            Write-Information "Working on $APIKey"
            if ($APIKey -notin $KnownExtensions) {
                if ($Body.$APIKey.APIKey -and $Body.$APIKey.APIKey -ne 'SentToKeyVault') {
                    Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Ignored an API key sent for unknown extension '$APIKey'." -Sev 'Warning'
                    $Body.$APIKey.APIKey = ''
                }
            } elseif ($Body.$APIKey.APIKey -eq 'SentToKeyVault' -or $Body.$APIKey.APIKey -eq '') {
                Write-Information 'Not sending to keyvault. Key previously set or left blank.'
            } else {
                Write-Information 'writing API Key to keyvault, and clearing.'
                Write-Information "$env:WEBSITE_DEPLOYMENT_ID"
                if ($Body.$APIKey.APIKey) {
                    Set-ExtensionAPIKey -Extension $APIKey -APIKey $Body.$APIKey.APIKey
                }
                if ($Body.$APIKey.PSObject.Properties.Name -notcontains 'APIKey') {
                    $Body.$APIKey | Add-Member -MemberType NoteProperty -Name APIKey -Value 'SentToKeyVault'
                } else {
                    $Body.$APIKey.APIKey = 'SentToKeyVault'
                }
            }
            $Body.$APIKey = $Body.$APIKey | Select-Object * -ExcludeProperty ResetPassword
        }
        $Body = $Body | Select-Object * -ExcludeProperty APIKey, Enabled | ConvertTo-Json -Depth 10 -Compress
        $Config = @{
            'PartitionKey' = 'CippExtensions'
            'RowKey'       = 'Config'
            'config'       = [string]$Body
        }

        Add-CIPPAzDataTableEntity @Table -Entity $Config -Force | Out-Null

        #Write-Information ($Request.Headers | ConvertTo-Json)
        $AddObject = @{
            PartitionKey = 'InstanceProperties'
            RowKey       = 'CIPPURL'
            Value        = [string]([System.Uri]$Headers.'x-ms-original-url').Host
        }
        Write-Information ($AddObject | ConvertTo-Json -Compress)
        $ConfigTable = Get-CIPPTable -tablename 'Config'
        Add-AzDataTableEntity @ConfigTable -Entity $AddObject -Force | Out-Null

        if ($ScheduleParameters.Count -gt 0) {
            Register-CIPPExtensionScheduledTasks @ScheduleParameters
        }
        Register-CIPPExtensionScheduledTasks

        # Credential fields are created or adopted on save so the mapping page shows them before the first sync
        if ($NinjaOneSettings.Enabled -eq $true -and ($NinjaOneSettings.IncludeLAPS -eq $true -or $NinjaOneSettings.IncludeBitLocker -eq $true)) {
            try {
                Initialize-NinjaOneCredentialField -Configuration ($Config.config | ConvertFrom-Json).NinjaOne
            } catch {
                $AddedText = "$AddedText NinjaOne credential fields were not prepared: $($_.Exception.Message)"
            }
        }
        # Alerts go to every ticketing integration that is on, so two on at once means two tickets per alert.
        $TicketingOn = [System.Collections.Generic.List[string]]::new()
        if ($HaloSettings.Enabled -eq $true) { $TicketingOn.Add('HaloPSA') }
        if ($Body.Syncro.Enabled -eq $true) { $TicketingOn.Add('Syncro') }
        if ($NinjaOneSettings.Enabled -eq $true -and $NinjaOneSettings.TicketingEnabled -eq $true) { $TicketingOn.Add('NinjaOne') }
        if ($TicketingOn.Count -gt 1) {
            $AddedText = "$AddedText Warning: $($TicketingOn -join ' and ') ticketing are all enabled, so every alert will raise a ticket in each. Keep one enabled."
        }
        $Result = "Successfully saved the extension configuration. $AddedText"
        $ChangedText = if ($Changes.Count -gt 0) {
            $Summary = $Changes.Keys | Group-Object { ($_ -split '\.', 2)[0] } | ForEach-Object { "$($_.Name) ($(($_.Group | ForEach-Object { ($_ -split '\.', 2)[1] }) -join ', '))" }
            " Changed: $($Summary -join '; ')."
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "$($Result.Trim())$ChangedText" -Sev 'Info' @ChangeLog
        $Result
    } catch {
        $Result = "Failed to save the extensions configuration: $($_.Exception.message) Linenumber: $($_.InvocationInfo.ScriptLineNumber)"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result
    }



    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Results }
        })

}
