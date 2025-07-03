using namespace System.Net

function Invoke-ListSharepointSettings {
    <#
    .SYNOPSIS
    List SharePoint admin settings for a tenant
    
    .DESCRIPTION
    Retrieves SharePoint admin settings for a tenant using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
        
    .NOTES
    Group: Teams & SharePoint
    Summary: List Sharepoint Settings
    Description: Retrieves SharePoint admin settings for a tenant using Microsoft Graph API including tenant-wide settings and configurations
    Tags: SharePoint,Settings,Admin,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Response: Returns SharePoint admin settings object from Microsoft Graph API
    Response: Contains various SharePoint tenant settings and configurations
    Response: Example: {
      "id": "sharepoint-settings",
      "allowedDomainGuidsForSyncApp": [],
      "availableManagedPathsForSiteCreation": [],
      "deletedUserPersonalSiteRetentionPeriodInDays": 30,
      "excludedFileExtensionsForSyncApp": [],
      "idleSessionSignOut": {
        "isEnabled": false,
        "warnAfter": 0,
        "signOutAfter": 0
      },
      "imageTaggingOption": "Basic",
      "isCommentingOnSitePagesEnabled": true,
      "isLoopEnabled": true,
      "isMacSyncAppEnabled": true,
      "isRequireAcceptingUserToMatchInvitedUserEnabled": false,
      "isResharingByExternalUsersEnabled": true,
      "isSharePointMobileNotificationEnabled": true,
      "isSharePointNewsfeedEnabled": false,
      "isSiteCreationEnabled": true,
      "isSiteCreationUIEnabled": true,
      "isSitePagesCreationEnabled": true,
      "isSitesStorageLimitAutomatic": true,
      "ownerAnonymousNotification": false,
      "sharingCapability": "ExternalUserAndGuestSharing",
      "sharingDomainRestrictionMode": "None",
      "storageQuota": 26214400,
      "tenantAllowOrBlockListPolicy": {
        "isEnabled": false,
        "isPAMEnabled": false
      }
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    #  XXX - Seems to be an unused endpoint? -Bobby


    # Interact with query parameters or the body of the request.
    $Tenant = $Request.Query.tenantFilter
    $Request = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings'

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Request)
        })

}
