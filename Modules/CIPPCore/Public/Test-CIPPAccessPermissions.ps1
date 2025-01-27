function Test-CIPPAccessPermissions {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Access Check',
        $ExecutingUser
    )

    $User = $request.headers.'x-ms-client-principal-name'
    Write-LogMessage -user $User -API $APINAME -message 'Started permissions check' -Sev 'Debug'
    $Messages = [System.Collections.Generic.List[string]]::new()
    $ErrorMessages = [System.Collections.Generic.List[string]]::new()
    $MissingPermissions = [System.Collections.Generic.List[string]]::new()
    $Links = [System.Collections.Generic.List[object]]::new()
    $AccessTokenDetails = [PSCustomObject]@{
        AppId             = ''
        AppName           = ''
        Audience          = ''
        AuthMethods       = ''
        IPAddress         = ''
        Name              = ''
        Scope             = ''
        TenantId          = ''
        UserPrincipalName = ''
    }
    $Success = $true
    try {
        Set-Location (Get-Item $PSScriptRoot).FullName
        $null = Get-CIPPAuthentication
        $GraphToken = Get-GraphToken -returnRefresh $true -SkipCache $true
        if ($GraphToken) {
            $GraphPermissions = Get-CippSamPermissions
        }
        if ($env:MSI_SECRET) {
            try {
                Disable-AzContextAutosave -Scope Process | Out-Null
                $AzSession = Connect-AzAccount -Identity

                $KV = $ENV:WEBSITE_DEPLOYMENT_ID
                $KeyVaultRefresh = Get-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -AsPlainText
                if ($ENV:RefreshToken -ne $KeyVaultRefresh) {
                    $Success = $false
                    $ErrorMessages.Add('Your refresh token does not match key vault, wait 30 minutes for the function app to update.') | Out-Null
                } else {
                    $Messages.Add('Your refresh token matches key vault.') | Out-Null
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -user $User -API $APINAME -tenant $tenant -message "Key vault exception: $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
            }
        } else {
            $Messages.Add('Your refresh token matches key vault.') | Out-Null
        }

        try {
            $AccessTokenDetails = Read-JwtAccessDetails -Token $GraphToken.access_token -erroraction SilentlyContinue
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $AccessTokenDetails = [PSCustomObject]@{
                Name        = ''
                AuthMethods = @()
            }
            Write-LogMessage -user $User -API $APINAME -tenant $tenant -message "Token exception: $($ErrorMessage.NormalizedError_) " -Sev 'Error' -LogData $ErrorMessage
            $Success = $false
        }

        if ($AccessTokenDetails.Name -eq '') {
            $ErrorMessages.Add('Your refresh token is invalid, check for line breaks or missing characters.') | Out-Null
            $Success = $false
        } else {
            if ($AccessTokenDetails.Name -match 'CIPP' -or $AccessTokenDetails.UserPrincipalName -match 'CIPP' -or $AccessTokenDetails.Name -match 'Service' -or $AccessTokenDetails.UserPrincipalName -match 'Service') {
                $Messages.Add('You are running CIPP as a service account.') | Out-Null
            } else {
                $ErrorMessages.Add('You do not appear to be running CIPP as a service account.') | Out-Null
                $Success = $false
                $Links.Add([PSCustomObject]@{
                        Text = 'Creating the CIPP Service Account'
                        Href = 'https://docs.cipp.app/setup/installation/creating-the-cipp-service-account-gdap-ready'
                    }
                ) | Out-Null
            }

            if ($AccessTokenDetails.AuthMethods -contains 'mfa') {
                $Messages.Add('Your access token contains the MFA claim.') | Out-Null
            } else {
                $ErrorMessages.Add('Your access token does not contain the MFA claim, Refresh your SAM tokens.') | Out-Null

                $Success = $false
                $Links.Add([PSCustomObject]@{
                        Text = 'MFA Troubleshooting'
                        Href = 'https://docs.cipp.app/troubleshooting/troubleshooting#multi-factor-authentication-troubleshooting'
                    }
                ) | Out-Null
            }
        }


        $MissingSamPermissions = $GraphPermissions.MissingPermissions
        if (($MissingSamPermissions.PSObject.Properties.Name | Measure-Object).Count -gt 0) {

            $MissingPermissions = foreach ($AppId in $MissingSamPermissions.PSObject.Properties.Name) {
                $ServicePrincipal = $GraphPermissions.UsedServicePrincipals | Where-Object -Property appId -EQ $AppId

                foreach ($Permission in $MissingSamPermissions.$AppId.applicationPermissions) {
                    [PSCustomObject]@{
                        Application  = $ServicePrincipal.displayName
                        Type         = 'Application'
                        PermissionId = $Permission.id
                        Permission   = $Permission.value
                    }
                }
                foreach ($Permission in $MissingSamPermissions.$AppId.delegatedPermissions) {
                    [PSCustomObject]@{
                        Application  = $ServicePrincipal.displayName
                        Type         = 'Delegated'
                        PermissionId = $Permission.id
                        Permission   = $Permission.value
                    }
                }
            }
            $Success = $false
            $Links.Add([PSCustomObject]@{
                    Text = 'Permissions'
                    Href = 'https://docs.cipp.app/setup/installation/permissions'
                }
            ) | Out-Null
        } else {
            $Messages.Add('You have all the required permissions.') | Out-Null
        }

        $LastUpdate = [DateTime]::SpecifyKind($GraphPermissions.Timestamp.DateTime, [DateTimeKind]::Utc)
        $CpvTable = Get-CippTable -tablename 'cpvtenants'
        $CpvRefresh = Get-CippAzDataTableEntity @CpvTable -Filter "PartitionKey eq 'Tenant'"
        $TenantList = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -ne $env:TenantID -and $_.Excluded -eq $false }
        $CPVRefreshList = [System.Collections.Generic.List[object]]::new()
        $CPVSuccess = $true
        foreach ($Tenant in $TenantList) {
            $LastRefresh = ($CpvRefresh | Where-Object { $_.RowKey -EQ $Tenant.customerId }).Timestamp.DateTime
            if ($LastRefresh -lt $LastUpdate) {
                $CPVSuccess = $false
                $CPVRefreshList.Add([PSCustomObject]@{
                        CustomerId        = $Tenant.customerId
                        DisplayName       = $Tenant.displayName
                        DefaultDomainName = $Tenant.DefaultDomainName
                        LastRefresh       = $LastRefresh
                    })
            }
        }
        if (!$CPVSuccess) {
            $ErrorMessages.Add('Some tenants need a CPV refresh.') | Out-Null
            $Success = $false
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APINAME -message "Permissions check failed: $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
        $ErrorMessages.Add("We could not connect to the API to retrieve the permissions. There might be a problem with the secure application model configuration. The returned error is: $($ErrorMessage.NormalizedError)") | Out-Null
        $Success = $false
    }

    if ($Success -eq $true) {
        $Messages.Add('No service account issues have been found. CIPP is ready for use.') | Out-Null
    }

    $AccessCheck = [PSCustomObject]@{
        AccessTokenDetails = $AccessTokenDetails
        Messages           = @($Messages)
        ErrorMessages      = @($ErrorMessages)
        MissingPermissions = @($MissingPermissions)
        CPVRefreshList     = @($CPVRefreshList)
        Links              = @($Links)
        Success            = $Success
    }

    $Table = Get-CIPPTable -TableName AccessChecks
    $Data = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AccessCheck' and RowKey eq 'AccessPermissions'"
    if ($Data) {
        $Data.Data = [string](ConvertTo-Json -InputObject $AccessCheck -Depth 10 -Compress)
    } else {
        $Data = @{
            PartitionKey = 'AccessCheck'
            RowKey       = 'AccessPermissions'
            Data         = [string](ConvertTo-Json -InputObject $AccessCheck -Depth 10 -Compress)
        }
    }
    try {
        Add-CIPPAzDataTableEntity @Table -Entity $Data -Force
    } catch {}

    return $AccessCheck
}
