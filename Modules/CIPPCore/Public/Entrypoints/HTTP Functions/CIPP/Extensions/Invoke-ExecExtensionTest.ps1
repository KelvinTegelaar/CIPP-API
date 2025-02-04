using namespace System.Net

Function Invoke-ExecExtensionTest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json)
    # Interact with query parameters or the body of the request.
    try {
        switch ($Request.query.extensionName) {
            'HaloPSA' {
                $token = Get-HaloToken -configuration $Configuration.HaloPSA
                $Results = [pscustomobject]@{'Results' = 'Successfully Connected to HaloPSA' }
            }
            'Gradient' {
                $GradientToken = Get-GradientToken -Configuration $Configuration.Gradient
                $ExistingIntegrations = Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization' -Method GET -Headers $GradientToken
                if ($ExistingIntegrations.Status -ne 'active') {
                    $ActivateRequest = Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/status/active' -Method PATCH -Headers $GradientToken
                }
                $Results = [pscustomobject]@{'Results' = 'Successfully Connected to Gradient' }

            }
            'CIPP-API' {
                $Results = [pscustomobject]@{'Results' = 'You cannot test the CIPP-API from CIPP. Please check the documentation on how to test the CIPP-API.' }
            }
            'NinjaOne' {
                $token = Get-NinjaOneToken -configuration $Configuration.NinjaOne
                $Results = [pscustomobject]@{'Results' = 'Successfully Connected to NinjaOne' }
            }
            'PWPush' {
                $Payload = 'This is a test from CIPP'
                $PasswordLink = New-PwPushLink -Payload $Payload
                if ($PasswordLink) {
                    $Results = [pscustomobject]@{'Results' = 'Successfully generated PWPush'; 'Link' = $PasswordLink }
                } else {
                    $Results = [pscustomobject]@{'Results' = 'PWPush is not enabled' }
                }
            }
            'Hudu' {
                Connect-HuduAPI -configuration $Configuration.Hudu
                $Version = Get-HuduAppInfo
                if ($Version.version) {
                    $Results = [pscustomobject]@{'Results' = ('Successfully Connected to Hudu, version: {0}' -f $Version.version) }
                } else {
                    $Results = [pscustomobject]@{'Results' = 'Failed to connect to Hudu' }
                }
            }
            'Sherweb' {
                $token = Get-SherwebAuthentication
                $Results = [pscustomobject]@{'Results' = 'Successfully Connected to Sherweb' }
            }
            'HIBP' {
                $ConnectionTest = Get-HIBPConnectionTest
                $Results = [pscustomobject]@{'Results' = 'Successfully Connected to HIBP' }
            }
            'GitHub' {
                $GitHubResponse = Invoke-GitHubApiRequest -Configuration $Configuration.GitHub -Method 'GET' -Path 'user' -Verbose
                $Results = [pscustomobject]@{ 'Results' = "Successfully connected to GitHub user: $($GitHubResponse.login)" }
            }
        }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to connect: $($_.Exception.Message). Line $($_.InvocationInfo.ScriptLineNumber)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
