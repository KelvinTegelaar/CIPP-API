Function Invoke-ExecExtensionTest {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json)
    # Interact with query parameters or the body of the request.
    try {
        switch ($Request.Query.extensionName) {
            'HaloPSA' {
                $token = Get-HaloToken -configuration $Configuration.HaloPSA
                if ($token) {
                    $Results = [pscustomobject]@{'Results' = 'Successfully Connected to HaloPSA' }
                } else {
                    $Results = [pscustomobject]@{'Results' = 'Failed to connect to HaloPSA, check your API credentials and try again.' }
                }
            }
            'Gradient' {
                $GradientToken = Get-GradientToken -Configuration $Configuration.Gradient
                if ($GradientToken) {
                    try {
                        $ExistingIntegrations = Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization' -Method GET -Headers $GradientToken
                        if ($ExistingIntegrations.Status -ne 'active') {
                            $ActivateRequest = Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/status/active' -Method PATCH -Headers $GradientToken
                        }
                        $Results = [pscustomobject]@{'Results' = 'Successfully Connected to Gradient' }
                    } catch {
                        $Results = [pscustomobject]@{'Results' = 'Failed to connect to Gradient, check your API credentials and try again.' }
                    }
                } else {
                    $Results = [pscustomobject]@{'Results' = 'Failed to connect to Gradient, check your API credentials and try again.' }
                }
            }
            'CIPP-API' {
                $Results = [pscustomobject]@{'Results' = 'You cannot test the CIPP-API from CIPP. Please check the documentation on how to test the CIPP-API.' }
            }
            'NinjaOne' {
                $token = Get-NinjaOneToken -configuration $Configuration.NinjaOne
                if ($token) {
                    $Results = [pscustomobject]@{'Results' = 'Successfully Connected to NinjaOne' }
                } else {
                    $Results = [pscustomobject]@{'Results' = 'Failed to connect to NinjaOne, check your API credentials and try again.' }
                }
            }
            'PWPush' {
                $Payload = 'This is a test from CIPP'
                $PasswordLink = New-PwPushLink -Payload $Payload
                if ($PasswordLink) {
                    $Results = [pscustomobject]@{Results = @(@{'resultText' = 'Successfully generated PWPush, hit the Copy to Clipboard button to retrieve the test.'; 'copyField' = $PasswordLink; 'state' = 'success' }) }
                } else {
                    $Results = [pscustomobject]@{'Results' = 'PWPush is not enabled' }
                }
            }
            'Hudu' {
                Connect-HuduAPI -configuration $Configuration
                $Version = Get-HuduAppInfo
                if ($Version.version) {
                    $Results = [pscustomobject]@{'Results' = ('Successfully Connected to Hudu, version: {0}' -f $Version.version) }
                } else {
                    $Results = [pscustomobject]@{'Results' = 'Failed to connect to Hudu, check your API credentials and try again.' }
                }
            }
            'Sherweb' {
                $token = Get-SherwebAuthentication
                if ($token) {
                    $Results = [pscustomobject]@{'Results' = 'Successfully Connected to Sherweb' }
                } else {
                    $Results = [pscustomobject]@{'Results' = 'Failed to connect to Sherweb, check your API credentials and try again.' }
                }
            }
            'HIBP' {
                $ConnectionTest = Get-HIBPConnectionTest
                $Results = [pscustomobject]@{'Results' = 'Successfully Connected to HIBP' }
            }
            'GitHub' {
                $GitHubResponse = Invoke-GitHubApiRequest -Method 'GET' -Path 'user' -ReturnHeaders
                if ($GitHubResponse.login) {
                    if ($GitHubResponse.Headers.'x-oauth-scopes') {
                        $Results = [pscustomobject]@{ 'Results' = "Successfully connected to GitHub user: $($GitHubResponse.login) with scopes: $($GitHubResponse.Headers.'x-oauth-scopes')" }
                    } else {
                        $Results = [pscustomobject]@{ 'Results' = "Successfully connected to GitHub user: $($GitHubResponse.login) using a Fine Grained PAT" }
                    }
                } else {
                    $Results = [pscustomobject]@{ 'Results' = 'Failed to connect to GitHub. Check your API credentials and try again.' }
                }
            }
        }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to connect: $($_.Exception.Message). Line $($_.InvocationInfo.ScriptLineNumber)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
