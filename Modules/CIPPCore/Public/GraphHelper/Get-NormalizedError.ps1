function Get-NormalizedError {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param (
        [string]$message
    )

    #Check if the message is valid JSON.
    try {
        $JSONMsg = $message | ConvertFrom-Json
    } catch {
    }
    #if the message is valid JSON, there can be multiple fields in which the error resides. These are:
    # $message.error.Innererror.Message 
    # $message.error.Message
    # $message.error.details.message
    # $message.error.innererror.internalException.message

    #We need to check if the message is in one of these fields, and if so, return it.
    if ($JSONMsg.error.innererror.message) {
        Write-Host 'innererror.message found'
        $message = $JSONMsg.error.innererror.message
    } elseif ($JSONMsg.error.message) {
        Write-Host 'error.message found'
        $message = $JSONMsg.error.message
    } elseif ($JSONMsg.error.details.message) {
        Write-Host 'error.details.message found'
        $message = $JSONMsg.error.details.message
    } elseif ($JSONMsg.error.innererror.internalException.message) {
        Write-Host 'error.innererror.internalException.message found'
        $message = $JSONMsg.error.innererror.internalException.message
    }
    
    
    #finally, put the message through the translator. If it's not in the list, just return the original message
    switch -Wildcard ($message) {
        'Request not applicable to target tenant.' { 'Required license not available for this tenant' }
        "Neither tenant is B2C or tenant doesn't have premium license" { 'This feature requires a P1 license or higher' }
        'Response status code does not indicate success: 400 (Bad Request).' { 'Error 400 occured. There is an issue with the token configuration for this tenant. Please perform an access check' }
        '*Microsoft.Skype.Sync.Pstn.Tnm.Common.Http.HttpResponseException*' { 'Could not connect to Teams Admin center - Tenant might be missing a Teams license' }
        '*Provide valid credential.*' { 'Error 400: There is an issue with your Exchange Token configuration. Please perform an access check for this tenant' }
        '*This indicate that a subscription within the tenant has lapsed*' { 'There is subscription for this service available, Check licensing information.' }
        '*User was not found.*' { 'The relationship between this tenant and the partner has been dissolved from the tenant side.' }
        '*The user or administrator has not consented to use the application*' { 'CIPP cannot access this tenant. Perform a CPV Refresh and Access Check via the settings menu' }
        '*AADSTS50020*' { 'AADSTS50020: The user you have used for your Secure Application Model is a guest in this tenant, or your are using GDAP and have not added the user to the correct group. Please delete the guest user to gain access to this tenant' }
        '*AADSTS50177' { 'AADSTS50177: The user you have used for your Secure Application Model is a guest in this tenant, or your are using GDAP and have not added the user to the correct group. Please delete the guest user to gain access to this tenant' }
        '*invalid or malformed*' { 'The request is malformed. Have you finished the SAM Setup?' }
        '*Windows Store repository apps feature is not supported for this tenant*' { 'This tenant does not have WinGet support available' }
        '*AADSTS650051*' { 'The application does not exist yet. Try again in 30 seconds.' }
        '*AppLifecycle_2210*' { 'Failed to call Intune APIs: Does the tenant have a license available?' }
        '*One or more added object references already exist for the following modified properties:*' { 'This user is already a member of this group.' }
        '*Microsoft.Exchange.Management.Tasks.MemberAlreadyExistsException*' { 'This user is already a member of this group.' }
        '*The property value exceeds the maximum allowed size (64KB)*' { 'One of the values exceeds the maximum allowed size (64KB).' }
        '*Unable to initialize the authorization context*' { 'Your GDAP configuration does not allow us to write to this tenant, please check your group mappings and tenant onboarding.' }
        '*Providers.Common.V1.CoreException*' { '403 (Access Denied) - We cannot connect to this tenant.' }
        '*Authentication failed. MFA required*' { 'Authentication failed. MFA required' }
        Default { $message }

    }
}
