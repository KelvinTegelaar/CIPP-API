function Invoke-ListHVEAccounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $Identity = $Request.Query.Identity
    $UseReportDB = $Request.Query.UseReportDB
    $ListBillingPolicies = $Request.Query.ListBillingPolicies

    try {
        if ($ListBillingPolicies -eq 'true') {
            # Return available HVE billing policies for the tenant
            $GraphRequest = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-BillingPolicy' -cmdParams @{
                ResourceType = 'HVE'
            })

            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @($GraphRequest)
                })
        }

        if ($Identity) {
            # Single account detail view
            $MailUser = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailUser' -cmdParams @{
                HVEAccount = $true
                Identity   = $Identity
            }

            $HVESettings = $null
            try {
                $HVESettings = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HVEAccountSettings' -cmdParams @{
                    Identity = $Identity
                }
            } catch {
                Write-Host "Could not retrieve HVE settings for $Identity : $($_.Exception.Message)"
            }

            $BillingPolicy = $null
            try {
                $BillingPolicy = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HVEAccountBillingPolicy' -cmdParams @{
                    Identity = $Identity
                }
            } catch {
                Write-Host "Could not retrieve billing policy for $Identity : $($_.Exception.Message)"
            }

            $GraphRequest = [PSCustomObject]@{
                displayName                   = $MailUser.DisplayName
                primarySmtpAddress            = $MailUser.PrimarySmtpAddress
                recipientType                 = 'MailUser'
                recipientTypeDetails          = 'HVEAccount'
                ExternalDirectoryObjectId     = $MailUser.ExternalDirectoryObjectId
                Alias                         = $MailUser.Alias
                WhenCreated                   = $MailUser.WhenCreated
                AdditionalEmailAddresses      = ($MailUser.EmailAddresses | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', '
                HiddenFromAddressListsEnabled = $MailUser.HiddenFromAddressListsEnabled
                ReplyTo                       = $HVESettings.ReplyTo
                BillingPolicyId               = $BillingPolicy.BillingPolicyId
                BillingPolicyName             = $BillingPolicy.BillingPolicyName
                SMTPServer                    = 'smtp.hve.mx.microsoft'
                SMTPPort                      = 587
                Authentication                = 'Basic (HVE credentials) or OAuth'
            }

            $StatusCode = [HttpStatusCode]::OK
            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = $GraphRequest
                })
        }

        if ($UseReportDB -eq 'true') {
            try {
                $HVEItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'HVEAccounts' | Where-Object { $_.RowKey -ne 'HVEAccounts-Count' }
                if (-not $HVEItems) {
                    $GraphRequest = @()
                } else {
                    $CacheTimestamp = ($HVEItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
                    $GraphRequest = foreach ($Item in $HVEItems) {
                        $Account = $Item.Data | ConvertFrom-Json
                        $Account | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
                        $Account
                    }
                }
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                Write-Host "Error retrieving HVE accounts from report database: $($_.Exception.Message)"
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        # Live EXO query
        $GraphRequest = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailUser' -cmdParams @{
            HVEAccount = $true
        } -Select 'DisplayName,PrimarySmtpAddress,ExternalDirectoryObjectId,Alias,WhenCreated,EmailAddresses,HiddenFromAddressListsEnabled') | Select-Object `
            @{ Name = 'displayName'; Expression = { $_.DisplayName } },
            @{ Name = 'primarySmtpAddress'; Expression = { $_.PrimarySmtpAddress } },
            @{ Name = 'recipientType'; Expression = { 'MailUser' } },
            @{ Name = 'recipientTypeDetails'; Expression = { 'HVEAccount' } },
            ExternalDirectoryObjectId,
            Alias,
            WhenCreated,
            @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } },
            HiddenFromAddressListsEnabled

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
