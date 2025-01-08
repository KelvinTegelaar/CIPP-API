using namespace System.Net

Function Invoke-ListUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $ConvertTable = Import-Csv ConversionTable.csv | Sort-Object -Property 'guid' -Unique
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $GraphFilter = $Request.Query.graphFilter
    $userid = $Request.Query.UserID

    $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)?`$top=999&`$filter=$GraphFilter&`$count=true" -tenantid $TenantFilter -ComplexFilter | ForEach-Object {
            $_ | Add-Member -MemberType NoteProperty -Name 'onPremisesSyncEnabled' -Value ([bool]($_.onPremisesSyncEnabled)) -Force
            $_ | Add-Member -MemberType NoteProperty -Name 'username' -Value ($_.userPrincipalName -split '@' | Select-Object -First 1) -Force
            $_ | Add-Member -MemberType NoteProperty -Name 'Aliases' -Value ($_.ProxyAddresses -join ', ') -Force
            $SkuID = $_.AssignedLicenses.skuid
            $_ | Add-Member -MemberType NoteProperty -Name 'LicJoined' -Value (($ConvertTable | Where-Object { $_.guid -in $skuid }).'Product_Display_Name' -join ', ') -Force
            $_ | Add-Member -MemberType NoteProperty -Name 'primDomain' -Value @{value = ($_.userPrincipalName -split '@' | Select-Object -Last 1); label = ($_.userPrincipalName -split '@' | Select-Object -Last 1); } -Force
            $_
        }
    } else {
        $Table = Get-CIPPTable -TableName 'cacheusers'
        $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
        if (!$Rows) {
            [PSCustomObject]@{
                Message = 'This function has been deprecated for all users, please use ListGraphRequest instead'
            }
        } else {
            $Rows.Data | ConvertFrom-Json | Select-Object $selectlist | ForEach-Object {
                $_.onPremisesSyncEnabled = [bool]($_.onPremisesSyncEnabled)
                $_.Aliases = $_.Proxyaddresses -join ', '
                $SkuID = $_.AssignedLicenses.skuid
                $_.LicJoined = ($ConvertTable | Where-Object { $_.guid -in $skuid }).'Product_Display_Name' -join ', '
                $_.primDomain = @{value = ($_.userPrincipalName -split '@' | Select-Object -Last 1) }
                $_
            }
        }
    }


    if ($userid -and $Request.query.IncludeLogonDetails) {
        $startDate = (Get-Date).AddDays(-7)
        $endDate = (Get-Date)
        $sessionid = Get-Random -Maximum 1000 -Minimum 1
        $SearchParam = @{
            SessionCommand = 'ReturnLargeSet'
            Operations     = @('UserLoggedIn', 'UserLoginFailed', 'TeamsSessionStarted', 'MailboxLogin')
            sessionid      = $sessionid
            startDate      = $startDate
            endDate        = $endDate
            UserIds        = @($GraphRequest.userPrincipalName)
        }
        $AuditlogsLogon = (New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Search-unifiedAuditLog' -cmdParams $SearchParam | Sort-Object -Property CreationDate | Select-Object -Last 1).auditdata | ConvertFrom-Json
        $Appname = '[{"Application Name":"ACOM Azure Website","Application IDs":"23523755-3a2b-41ca-9315-f81f3f566a95"},{"Application Name":"AEM-DualAuth","Application IDs":"69893ee3-dd10-4b1c-832d-4870354be3d8"},{"Application Name":"ASM Campaign Servicing","Application IDs":"0cb7b9ec-5336-483b-bc31-b15b5788de71"},{"Application Name":"Azure Advanced Threat Protection","Application IDs":"7b7531ad-5926-4f2d-8a1d-38495ad33e17"},{"Application Name":"Azure Data Lake","Application IDs":"e9f49c6b-5ce5-44c8-925d-015017e9f7ad"},{"Application Name":"Azure Lab Services Portal","Application IDs":"835b2a73-6e10-4aa5-a979-21dfda45231c"},{"Application Name":"Azure Portal","Application IDs":"c44b4083-3bb0-49c1-b47d-974e53cbdf3c"},{"Application Name":"AzureSupportCenter","Application IDs":"37182072-3c9c-4f6a-a4b3-b3f91cacffce"},{"Application Name":"Bing","Application IDs":"9ea1ad79-fdb6-4f9a-8bc3-2b70f96e34c7"},{"Application Name":"CPIM Service","Application IDs":"bb2a2e3a-c5e7-4f0a-88e0-8e01fd3fc1f4"},{"Application Name":"CRM Power BI Integration","Application IDs":"e64aa8bc-8eb4-40e2-898b-cf261a25954f"},{"Application Name":"Dataverse","Application IDs":"00000007-0000-0000-c000-000000000000"},{"Application Name":"Enterprise Roaming and Backup","Application IDs":"60c8bde5-3167-4f92-8fdb-059f6176dc0f"},{"Application Name":"IAM Supportability","Application IDs":"a57aca87-cbc0-4f3c-8b9e-dc095fdc8978"},{"Application Name":"IrisSelectionFrontDoor","Application IDs":"16aeb910-ce68-41d1-9ac3-9e1673ac9575"},{"Application Name":"MCAPI Authorization Prod","Application IDs":"d73f4b35-55c9-48c7-8b10-651f6f2acb2e"},{"Application Name":"Media Analysis and Transformation Service","Application IDs":"944f0bd1-117b-4b1c-af26-804ed95e767e<br>0cd196ee-71bf-4fd6-a57c-b491ffd4fb1e"},{"Application Name":"Microsoft 365 Support Service","Application IDs":"ee272b19-4411-433f-8f28-5c13cb6fd407"},{"Application Name":"Microsoft App Access Panel","Application IDs":"0000000c-0000-0000-c000-000000000000"},{"Application Name":"Microsoft Approval Management","Application IDs":"65d91a3d-ab74-42e6-8a2f-0add61688c74<br>38049638-cc2c-4cde-abe4-4479d721ed44"},{"Application Name":"Microsoft Authentication Broker","Application IDs":"29d9ed98-a469-4536-ade2-f981bc1d605e"},{"Application Name":"Microsoft Azure CLI","Application IDs":"04b07795-8ddb-461a-bbee-02f9e1bf7b46"},{"Application Name":"Microsoft Azure PowerShell","Application IDs":"1950a258-227b-4e31-a9cf-717495945fc2"},{"Application Name":"Microsoft Bing Search","Application IDs":"cf36b471-5b44-428c-9ce7-313bf84528de"},{"Application Name":"Microsoft Bing Search for Microsoft Edge","Application IDs":"2d7f3606-b07d-41d1-b9d2-0d0c9296a6e8"},{"Application Name":"Microsoft Bing Default Search Engine","Application IDs":"1786c5ed-9644-47b2-8aa0-7201292175b6"},{"Application Name":"Microsoft Defender for Cloud Apps","Application IDs":"3090ab82-f1c1-4cdf-af2c-5d7a6f3e2cc7"},{"Application Name":"Microsoft Docs","Application IDs":"18fbca16-2224-45f6-85b0-f7bf2b39b3f3"},{"Application Name":"Microsoft Dynamics ERP","Application IDs":"00000015-0000-0000-c000-000000000000"},{"Application Name":"Microsoft Edge Insider Addons Prod","Application IDs":"6253bca8-faf2-4587-8f2f-b056d80998a7"},{"Application Name":"Microsoft Exchange Online Protection","Application IDs":"00000007-0000-0ff1-ce00-000000000000"},{"Application Name":"Microsoft Forms","Application IDs":"c9a559d2-7aab-4f13-a6ed-e7e9c52aec87"},{"Application Name":"Microsoft Graph","Application IDs":"00000003-0000-0000-c000-000000000000"},{"Application Name":"Microsoft Intune Web Company Portal","Application IDs":"74bcdadc-2fdc-4bb3-8459-76d06952a0e9"},{"Application Name":"Microsoft Intune Windows Agent","Application IDs":"fc0f3af4-6835-4174-b806-f7db311fd2f3"},{"Application Name":"Microsoft Learn","Application IDs":"18fbca16-2224-45f6-85b0-f7bf2b39b3f3"},{"Application Name":"Microsoft Office","Application IDs":"d3590ed6-52b3-4102-aeff-aad2292ab01c"},{"Application Name":"Microsoft Office 365 Portal","Application IDs":"00000006-0000-0ff1-ce00-000000000000"},{"Application Name":"Microsoft Office Web Apps Service","Application IDs":"67e3df25-268a-4324-a550-0de1c7f97287"},{"Application Name":"Microsoft Online Syndication Partner Portal","Application IDs":"d176f6e7-38e5-40c9-8a78-3998aab820e7"},{"Application Name":"Microsoft password reset service","Application IDs":"93625bc8-bfe2-437a-97e0-3d0060024faa"},{"Application Name":"Microsoft Power BI","Application IDs":"871c010f-5e61-4fb1-83ac-98610a7e9110"},{"Application Name":"Microsoft Storefronts","Application IDs":"28b567f6-162c-4f54-99a0-6887f387bbcc"},{"Application Name":"Microsoft Stream Portal","Application IDs":"cf53fce8-def6-4aeb-8d30-b158e7b1cf83"},{"Application Name":"Microsoft Substrate Management","Application IDs":"98db8bd6-0cc0-4e67-9de5-f187f1cd1b41"},{"Application Name":"Microsoft Support","Application IDs":"fdf9885b-dd37-42bf-82e5-c3129ef5a302"},{"Application Name":"Microsoft Teams","Application IDs":"1fec8e78-bce4-4aaf-ab1b-5451cc387264"},{"Application Name":"Microsoft Teams Services","Application IDs":"cc15fd57-2c6c-4117-a88c-83b1d56b4bbe"},{"Application Name":"Microsoft Teams Web Client","Application IDs":"5e3ce6c0-2b1f-4285-8d4b-75ee78787346"},{"Application Name":"Microsoft Whiteboard Services","Application IDs":"95de633a-083e-42f5-b444-a4295d8e9314"},{"Application Name":"O365 Suite UX","Application IDs":"4345a7b9-9a63-4910-a426-35363201d503"},{"Application Name":"Office 365 Exchange Online","Application IDs":"00000002-0000-0ff1-ce00-000000000000"},{"Application Name":"Office 365 Management","Application IDs":"00b41c95-dab0-4487-9791-b9d2c32c80f2"},{"Application Name":"Office 365 Search Service","Application IDs":"66a88757-258c-4c72-893c-3e8bed4d6899"},{"Application Name":"Office 365 SharePoint Online","Application IDs":"00000003-0000-0ff1-ce00-000000000000"},{"Application Name":"Office Delve","Application IDs":"94c63fef-13a3-47bc-8074-75af8c65887a"},{"Application Name":"Office Online Add-in SSO","Application IDs":"93d53678-613d-4013-afc1-62e9e444a0a5"},{"Application Name":"Office Online Client AAD- Augmentation Loop","Application IDs":"2abdc806-e091-4495-9b10-b04d93c3f040"},{"Application Name":"Office Online Client AAD- Loki","Application IDs":"b23dd4db-9142-4734-867f-3577f640ad0c"},{"Application Name":"Office Online Client AAD- Maker","Application IDs":"17d5e35f-655b-4fb0-8ae6-86356e9a49f5"},{"Application Name":"Office Online Client MSA- Loki","Application IDs":"b6e69c34-5f1f-4c34-8cdf-7fea120b8670"},{"Application Name":"Office Online Core SSO","Application IDs":"243c63a3-247d-41c5-9d83-7788c43f1c43"},{"Application Name":"Office Online Search","Application IDs":"a9b49b65-0a12-430b-9540-c80b3332c127"},{"Application Name":"Office.com","Application IDs":"4b233688-031c-404b-9a80-a4f3f2351f90"},{"Application Name":"Office365 Shell WCSS-Client","Application IDs":"89bee1f7-5e6e-4d8a-9f3d-ecd601259da7"},{"Application Name":"OfficeClientService","Application IDs":"0f698dd4-f011-4d23-a33e-b36416dcb1e6"},{"Application Name":"OfficeHome","Application IDs":"4765445b-32c6-49b0-83e6-1d93765276ca"},{"Application Name":"OfficeShredderWacClient","Application IDs":"4d5c2d63-cf83-4365-853c-925fd1a64357"},{"Application Name":"OMSOctopiPROD","Application IDs":"62256cef-54c0-4cb4-bcac-4c67989bdc40"},{"Application Name":"OneDrive SyncEngine","Application IDs":"ab9b8c07-8f02-4f72-87fa-80105867a763"},{"Application Name":"OneNote","Application IDs":"2d4d3d8e-2be3-4bef-9f87-7875a61c29de"},{"Application Name":"Outlook Mobile","Application IDs":"27922004-5251-4030-b22d-91ecd9a37ea4"},{"Application Name":"Partner Customer Delegated Admin Offline Processor","Application IDs":"a3475900-ccec-4a69-98f5-a65cd5dc5306"},{"Application Name":"Password Breach Authenticator","Application IDs":"bdd48c81-3a58-4ea9-849c-ebea7f6b6360"},{"Application Name":"Power BI Service","Application IDs":"00000009-0000-0000-c000-000000000000"},{"Application Name":"SharedWithMe","Application IDs":"ffcb16e8-f789-467c-8ce9-f826a080d987"},{"Application Name":"SharePoint Online Web Client Extensibility","Application IDs":"08e18876-6177-487e-b8b5-cf950c1e598c"},{"Application Name":"Signup","Application IDs":"b4bddae8-ab25-483e-8670-df09b9f1d0ea"},{"Application Name":"Skype for Business Online","Application IDs":"00000004-0000-0ff1-ce00-000000000000"},{"Application Name":"Sway","Application IDs":"905fcf26-4eb7-48a0-9ff0-8dcc7194b5ba"},{"Application Name":"Universal Store Native Client","Application IDs":"268761a2-03f3-40df-8a8b-c3db24145b6b"},{"Application Name":"Vortex [wsfed enabled]","Application IDs":"5572c4c0-d078-44ce-b81c-6cbf8d3ed39e"},{"Application Name":"Windows Azure Active Directory","Application IDs":"00000002-0000-0000-c000-000000000000"},{"Application Name":"Windows Azure Service Management API","Application IDs":"797f4846-ba00-4fd7-ba43-dac1f8f63013"},{"Application Name":"WindowsDefenderATP Portal","Application IDs":"a3b79187-70b2-4139-83f9-6016c58cd27b"},{"Application Name":"Windows Search","Application IDs":"26a7ee05-5602-4d76-a7ba-eae8b7b67941"},{"Application Name":"Windows Spotlight","Application IDs":"1b3c667f-cde3-4090-b60b-3d2abd0117f0"},{"Application Name":"Windows Store for Business","Application IDs":"45a330b1-b1ec-4cc1-9161-9f03992aa49f"},{"Application Name":"Yammer","Application IDs":"00000005-0000-0ff1-ce00-000000000000"},{"Application Name":"Yammer Web","Application IDs":"c1c74fed-04c9-4704-80dc-9f79a2e515cb"},{"Application Name":"Yammer Web Embed","Application IDs":"e1ef36fd-b883-4dbf-97f0-9ece4b576fc6"}]' | ConvertFrom-Json | Where-Object -Property 'Application IDs' -EQ $AuditlogsLogon.applicationId
        $LastSignIn = [PSCustomObject]@{
            AppDisplayName  = if ($AppName) { $AppName.'Application Name' } else { "$($AuditlogsLogon.Workload) - $($AuditlogsLogon.ApplicationId) " }
            CreatedDateTime = $AuditlogsLogon.CreationTime
            Id              = $AuditlogsLogon.errorNumber
            Status          = $AuditlogsLogon.ResultStatus
        }
        $GraphRequest = $GraphRequest | Select-Object *,
        @{ Name = 'LastSigninApplication'; Expression = { $LastSignIn.AppDisplayName } },
        @{ Name = 'LastSigninDate'; Expression = { $($LastSignIn.CreatedDateTime | Out-String) } },
        @{ Name = 'LastSigninStatus'; Expression = { $AuditlogsLogon.operation } },
        @{ Name = 'LastSigninResult'; Expression = { $LastSignIn.status } },
        @{ Name = 'LastSigninFailureReason'; Expression = { if ($LastSignIn.Id -eq 0) { 'Sucessfully signed in' } else { $LastSignIn.Id } } }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
