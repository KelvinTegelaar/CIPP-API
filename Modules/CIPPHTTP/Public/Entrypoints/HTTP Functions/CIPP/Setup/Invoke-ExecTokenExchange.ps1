function Invoke-ExecTokenExchange {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Get the key vault name
    $KV = $env:WEBSITE_DEPLOYMENT_ID
    $APIName = $Request.Params.CIPPEndpoint

    try {
        if (!$Request.Body) {
            Write-LogMessage -API $APIName -message 'Request body is missing' -Sev 'Error'
            throw 'Request body is missing'
        }

        $TokenRequest = $Request.Body.tokenRequest
        $TokenUrl = $Request.Body.tokenUrl
        $TenantId = $Request.Body.tenantId

        if (!$TokenRequest -or !$TokenUrl) {
            Write-LogMessage -API $APIName -message 'Missing required parameters: tokenRequest or tokenUrl' -Sev 'Error'
            throw 'Missing required parameters: tokenRequest or tokenUrl'
        }

        Write-LogMessage -API $APIName -message "Making token request to $TokenUrl" -Sev 'Info'

        # Make sure we get the latest authentication
        $auth = Get-CIPPAuthentication

        # Check if environment variable is already set and not the placeholder value
        if ($auth -and $env:ApplicationSecret -and $env:ApplicationSecret -ne 'AppSecret') {
            $ClientSecret = $env:ApplicationSecret
            Write-LogMessage -API $APIName -message 'Using client secret from environment variable' -Sev 'Debug'
        } elseif ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            $ClientSecret = $Secret.applicationsecret
            Write-LogMessage -API $APIName -message 'Retrieved client secret from development secrets' -Sev 'Debug'
        } else {
            try {
                $ClientSecret = (Get-CippKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -AsPlainText)
                Write-LogMessage -API $APIName -message 'Retrieved client secret from key vault' -Sev 'Debug'
            } catch {
                Write-LogMessage -API $APIName -message "Failed to retrieve client secret: $($_.Exception.Message)" -Sev 'Error'
                throw "Failed to retrieve client secret: $($_.Exception.Message)"
            }
        }

        # Check if client secret is still the default placeholder value from ARM template
        if (!$ClientSecret -or $ClientSecret -eq 'AppSecret') {
            Write-LogMessage -API $APIName -message 'Client secret is not configured' -Sev 'Error'
            throw 'Application secret has not been configured. Please complete the setup process first.'
        }

        # Convert token request to form data and add client secret
        $FormData = @{}
        foreach ($key in $TokenRequest.PSObject.Properties.Name) {
            $FormData[$key] = $TokenRequest.$key
        }

        # Add client_secret to the form data if not already present
        if (!$FormData.ContainsKey('client_secret')) {
            $FormData['client_secret'] = $ClientSecret
        }

        Write-Host "Posting this data: $($FormData | ConvertTo-Json -Depth 15)"
        $Results = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $FormData -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -SkipHttpErrorCheck
    } catch {
        $ErrorMessage = $_.Exception
        $Results = @{
            error             = 'server_error'
            error_description = "Token exchange failed: $ErrorMessage"
        }
    }
    if ($Results.error) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Results
                Headers    = @{'Content-Type' = 'application/json' }
            })
    } else {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
                Headers    = @{'Content-Type' = 'application/json' }
            })
    }
}
