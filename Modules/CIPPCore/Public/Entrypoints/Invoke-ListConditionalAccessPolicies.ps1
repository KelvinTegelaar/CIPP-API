    using namespace System.Net

    Function Invoke-ListConditionalAccessPolicies {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


function Get-LocationNameFromId {
    [CmdletBinding()]
    param (
        [Parameter()]
        $ID,
        
        [Parameter(Mandatory = $true)]
        $Locations
    )
    if ($id -eq 'All') {
        return 'All'
    }
    $DisplayName = $Locations | Where-Object { $_.id -eq $ID } | Select-Object -ExpandProperty DisplayName
    if ([string]::IsNullOrEmpty($displayName)) {
        return  $ID
    }
    else {
        return $DisplayName
    }
}

function Get-RoleNameFromId {
    [CmdletBinding()]
    param (
        [Parameter()]
        $ID,
        
        [Parameter(Mandatory = $true)]
        $RoleDefinitions
    )
    if ($id -eq 'All') {
        return 'All'
    }
    $DisplayName = $RoleDefinitions | Where-Object { $_.id -eq $ID } | Select-Object -ExpandProperty DisplayName
    if ([string]::IsNullOrEmpty($displayName)) {
        return $ID
    }
    else {
        return $DisplayName
    }
}

function Get-UserNameFromId {
    [CmdletBinding()]
    param (
        [Parameter()]
        $ID,
        
        [Parameter(Mandatory = $true)]
        $Users
    )
    if ($id -eq 'All') {
        return 'All'
    }
    $DisplayName = $Users | Where-Object { $_.id -eq $ID } | Select-Object -ExpandProperty DisplayName
    if ([string]::IsNullOrEmpty($displayName)) {
        return $ID
    }
    else {
        return $DisplayName
    }
}

function Get-GroupNameFromId {
    param (
        [Parameter()]
        $ID,

        [Parameter(Mandatory = $true)]
        $Groups
    )
    if ($id -eq 'All') {
        return 'All'
    }
    $DisplayName = $Groups | Where-Object { $_.id -eq $ID } | Select-Object -ExpandProperty DisplayName
    if ([string]::IsNullOrEmpty($displayName)) {
        return "No Data"
    }
    else {
        return $DisplayName
    }
}

function Get-ApplicationNameFromId {
    [CmdletBinding()]
    param (
        [Parameter()]
        $ID,
        
        [Parameter(Mandatory = $true)]
        $Applications
    )
    if ($id -eq 'All') {
        return 'All'
    }
    switch ($id) {
        00000004-0000-0ff1-ce00-000000000000 { $return = 'Microsoft.Lync' }
        00000006-0000-0ff1-ce00-000000000000 { $return = 'Microsoft.Office365Portal' }
        00000003-0000-0ff1-ce00-000000000000 { $return = 'Microsoft.SharePoint ' }
        00000005-0000-0000-c000-000000000000 { $return = 'Microsoft.Azure.Workflow' }
        00000009-0000-0000-c000-000000000000 { $return = 'Microsoft.Azure.AnalysisServices' }
        00000002-0000-0ff1-ce00-000000000000 { $return = 'Microsoft.Exchange' }
        00000007-0000-0ff1-ce00-000000000000 { $return = 'Microsoft.ExchangeOnlineProtection' }
        00000002-0000-0000-c000-000000000000 { $return = 'Microsoft.Azure.ActiveDirectory' }
        8fca0a66-c008-4564-a876-ab3ae0fd5cff { $return = 'Microsoft.SMIT' }
        0000000b-0000-0000-c000-000000000000 { $return = 'Microsoft.SellerDashboard' }
        0000000f-0000-0000-c000-000000000000 { $return = 'Microsoft.Azure.GraphExplorer' }
        0000000c-0000-0000-c000-000000000000 { $return = 'Microsoft App Access Panel' }
        00000013-0000-0000-c000-000000000000 { $return = 'Microsoft.Azure.Portal' }
        00000010-0000-0000-c000-000000000000 { $return = 'Microsoft.Azure.GraphStore' }
        93ee9413-cf4c-4d4e-814b-a91ff20a01bd { $return = 'Workflow' }
        aa9ecb1e-fd53-4aaa-a8fe-7a54de2c1334 { $return = 'Microsoft.Office365.Configure' }
        797f4846-ba00-4fd7-ba43-dac1f8f63013 { $return = 'Windows Azure Service Management API' }
        00000005-0000-0ff1-ce00-000000000000 { $return = 'Microsoft.YammerEnterprise' }
        601d4e27-7bb3-4dee-8199-90d47d527e1c { $return = 'Microsoft.Office365.ChangeManagement' }
        6f82282e-0070-4e78-bc23-e6320c5fa7de { $return = 'Microsoft.DiscoveryService' }
        0f698dd4-f011-4d23-a33e-b36416dcb1e6 { $return = 'Microsoft.OfficeClientService' }
        67e3df25-268a-4324-a550-0de1c7f97287 { $return = 'Microsoft.OfficeWebAppsService' }
        ab27a73e-a3ba-4e43-8360-8bcc717114d8 { $return = 'Microsoft.OfficeModernCalendar' }
        aedca418-a84d-430d-ab84-0b1ef06f318f { $return = 'Workflow' }
        595d87a1-277b-4c0a-aa7f-44f8a068eafc { $return = 'Microsoft.SupportTicketSubmission' }
        e3583ad2-c781-4224-9b91-ad15a8179ba0 { $return = 'Microsoft.ExtensibleRealUserMonitoring' }
        b645896d-566e-447e-8f7f-e2e663b5d182 { $return = 'OpsDashSharePointApp' }
        48229a4a-9f1d-413a-8b96-4c02462c0360 { $return = 'OpsDashSharePointApp' }
        48717084-a59c-4306-9dc4-3f618dbecdf9 { $return = '"Napa" Office 365 Development Tools' }
        c859ff33-eb41-4ba6-8093-a2c5153bbd7c { $return = 'Workflow' }
        67cad61c-3411-48d7-ab73-561c64f11ed6 { $return = 'Workflow' }
        914ed757-9257-4200-b68e-a2bed2f12c5a { $return = 'RbacBackfill' }
        499b84ac-1321-427f-aa17-267ca6975798 { $return = 'Microsoft.VisualStudio.Online' }
        b2590339-0887-4e94-93aa-13357eb510d7 { $return = 'Workflow' }
        0000001b-0000-0000-c000-000000000000 { $return = 'Microsoft Power BI Information Service' }
        89f80565-bfac-4c01-9535-9f0eba332ffe { $return = 'Power BI' }
        433895fb-4ec7-45c3-a53c-c44d10f80d5b { $return = 'Compromised Account Service' }
        d7c17728-4f1e-4a1e-86cf-7e0adf3fe903 { $return = 'Workflow' }
        17ef6d31-381f-4783-b186-7b440a3c85c1 { $return = 'Workflow' }
        00000012-0000-0000-c000-000000000000 { $return = 'Microsoft.Azure.RMS' }
        81ce94d4-9422-4c0d-a4b9-3250659366ce { $return = 'Workflow' }
        8d3a7d3c-c034-4f19-a2ef-8412952a9671 { $return = 'MicrosoftOffice' }
        0469d4cd-df37-4d93-8a61-f8c75b809164 { $return = 'Microsoft Policy Administration Service' }
        31d3f3f5-7267-45a8-9549-affb00110054 { $return = 'Windows Azure RemoteApp Service' }
        4e004241-32db-46c2-a86f-aaaba29bea9c { $return = 'Workflow' }
        748d098e-7a3b-436d-8b0a-006a58b29647 { $return = 'Workflow' }
        dbf08535-1d3b-4f89-bf54-1d48dd613a61 { $return = 'Workflow' }
        ed9fe1ef-25a4-482f-9981-2b60f91e2448 { $return = 'Workflow' }
        8ad28d50-ee26-42fc-8a29-e41ea38461f2 { $return = 'Office365RESTAPIExplorer.Office365App' }
        38285dce-a13d-4107-9b04-3016b941bb3a { $return = 'BasicDataOperationsREST' }
        92bb96c8-321c-47f9-bcc5-8849490c2b07 { $return = 'BasicSelfHostedAppREST' }
        488a57a0-00e2-4817-8c8d-cf8a15a994d2 { $return = 'WindowsFormsApplication2.Office365App' }
        11c174dc-1945-4a9a-a36b-c79a0f246b9b { $return = 'AzureApplicationInsights' }
        e6acb561-0d94-4287-bd3a-3169f421b112 { $return = 'Tutum' }
        7b77b3a2-8490-49e1-8842-207cd0899af9 { $return = 'Nearpod' }
        0000000a-0000-0000-c000-000000000000 { $return = 'Microsoft.Intune' }
        93625bc8-bfe2-437a-97e0-3d0060024faa { $return = 'SelfServicePasswordReset' }
        dee7ba80-6a55-4f3b-a86c-746a9231ae49 { $return = 'MicrosoftAppPlatEMA' }
        803ee9ca-3f7f-4824-bd6e-0b99d720c35c { $return = 'Azure Media Service' }
        2d4d3d8e-2be3-4bef-9f87-7875a61c29de { $return = 'OneNote' }
        8d40666e-5abf-45f6-a5e7-b7192d6d56ed { $return = 'Workflow' }
        262044b1-e2ce-469f-a196-69ab7ada62d3 { $return = 'Backup Management Service' }
        087a2c70-c89e-463f-8dd3-e3959eabb1a9 { $return = 'Microsoft Profile Service Platform Service' }
        7cd684f4-8a78-49b0-91ec-6a35d38739ba { $return = 'Azure Logic Apps' }
        c5393580-f805-4401-95e8-94b7a6ef2fc2 { $return = 'Office 365 Management APIs' }
        96231a05-34ce-4eb4-aa6a-70759cbb5e83 { $return = 'MicrosoftAzureRedisCache' }
        b8340c3b-9267-498f-b21a-15d5547fd85e { $return = 'Hyper-V Recovery Manager' }
        abfa0a7c-a6b6-4736-8310-5855508787cd { $return = 'Microsoft.Azure.WebSites' }
        c44b4083-3bb0-49c1-b47d-974e53cbdf3c { $return = 'IbizaPortal' }
        905fcf26-4eb7-48a0-9ff0-8dcc7194b5ba { $return = 'Sway' }
        b10686fd-6ba8-49f2-a3cd-67e4d2f52ac8 { $return = 'NovoEd' }
        c606301c-f764-4e6b-aa45-7caaaea93c9a { $return = 'OfficeStore' }
        569e8598-685b-4ba2-8bff-5bced483ac46 { $return = 'Evercontact' }
        20a23a2f-8c32-4de7-8063-8c8f909602c0 { $return = 'Workflow' }
        aaf214cc-8013-4b95-975f-13203ae36039 { $return = 'Power BI Tiles' }
        d88a361a-d488-4271-a13f-a83df7dd99c2 { $return = 'IDML Graph Resolver Service and CAD' }
        dff9b531-6290-4620-afce-26826a62a4e7 { $return = 'DocuSign' }
        01cb2876-7ebd-4aa4-9cc9-d28bd4d359a9 { $return = 'Device Registration Service' }
        3290e3f7-d3ac-4165-bcef-cf4874fc4270 { $return = 'Smartsheet' }
        a4ee6867-8640-4495-b1fd-8b26037a5bd3 { $return = 'Workflow' }
        aa0e3dd4-df02-478d-869e-fc61dd71b6e8 { $return = 'Workflow' }
        0f6edad5-48f2-4585-a609-d252b1c52770 { $return = 'AIGraphClient' }
        0c8139b5-d545-4448-8d2b-2121bb242680 { $return = 'BillingExtension' }
        475226c6-020e-4fb2-8a90-7a972cbfc1d4 { $return = 'KratosAppsService' }
        39624784-6cbe-4a60-afbe-9f46d10fdb27 { $return = 'SkypeForBusinessRemotePowershell' }
        8bdebf23-c0fe-4187-a378-717ad86f6a53 { $return = 'ResourceHealthRP' }
        c161e42e-d4df-4a3d-9b42-e7a3c31f59d4 { $return = 'MicrosoftIntuneAPI' }
        9cb77803-d937-493e-9a3b-4b49de3f5a74 { $return = 'MicrosoftIntuneServiceDiscovery' }
        ddbf3205-c6bd-46ae-8127-60eb93363864 { $return = 'Microsoft Azure Batch' }
        80ccca67-54bd-44ab-8625-4b79c4dc7775 { $return = 'ComplianceCenter' }
        0a5f63c0-b750-4f38-a71c-4fc0d58b89e2 { $return = 'Microsoft Mobile Application Management' }
        e1335bb1-2aec-4f92-8140-0e6e61ae77e5 { $return = 'CIWebService' }
        75018fbe-21fe-4a57-b63c-83252b5eaf16 { $return = 'TeamImprover - Team Organization Chart' }
        a393296b-5695-4463-97cb-9fa8638a494a { $return = 'My SharePoint Sites' }
        fe217466-5583-431c-9531-14ff7268b7b3 { $return = 'Microsoft Education' }
        5bfe8a29-054e-4348-9e7a-3981b26b125f { $return = 'Bing Places for Business' }
        eaf8a961-f56e-47eb-9ffd-936e22a554ef { $return = 'DevilFish' }
        4b4b1d56-1f03-47d9-a0a3-87d4afc913c9 { $return = 'Wunderlist' }
        00000003-0000-0000-c000-000000000000 { $return = 'Microsoft Graph' }
        60e6cd67-9c8c-4951-9b3c-23c25a2169af { $return = 'Compute Resource Provider' }
        507bc9da-c4e2-40cb-96a7-ac90df92685c { $return = 'Office365Reports' }
        09abbdfd-ed23-44ee-a2d9-a627aa1c90f3 { $return = 'ProjectWorkManagement' }
        28ec9756-deaf-48b2-84d5-a623b99af263 { $return = 'Office Personal Assistant at Work Service' }
        9e4a5442-a5c9-4f6f-b03f-5b9fcaaf24b1 { $return = 'OfficeServicesManager' }
        3138fe80-4087-4b04-80a6-8866c738028a { $return = 'SharePoint Notification Service' }
        d2a0a418-0aac-4541-82b2-b3142c89da77 { $return = 'MicrosoftAzureOperationalInsights' }
        2cf9eb86-36b5-49dc-86ae-9a63135dfa8c { $return = 'AzureTrafficManagerandDNS' }
        32613fc5-e7ac-4894-ac94-fbc39c9f3e4a { $return = 'OAuth Sandbox' }
        925eb0d0-da50-4604-a19f-bd8de9147958 { $return = 'Groupies Web Service' }
        e4ab13ed-33cb-41b4-9140-6e264582cf85 { $return = 'Azure SQL Database Backup To Azure Backup Vault' }
        ad230543-afbe-4bb4-ac4f-d94d101704f8 { $return = 'Apiary for Power BI' }
        11cd3e2e-fccb-42ad-ad00-878b93575e07 { $return = 'Automated Call Distribution' }
        de17788e-c765-4d31-aba4-fb837cfff174 { $return = 'Skype for Business Management Reporting and Analytics' }
        65d91a3d-ab74-42e6-8a2f-0add61688c74 { $return = 'Microsoft Approval Management' }
        5225545c-3ebd-400f-b668-c8d78550d776 { $return = 'Office Agent Service' }
        1cda9b54-9852-4a5a-96d4-c2ab174f9edf { $return = 'O365Account' }
        4747d38e-36c5-4bc3-979b-b0ef74df54d1 { $return = 'PushChannel' }
        b97b6bd4-a49f-4a0c-af18-af507d1da76c { $return = 'Office Shredding Service' }
        d4ebce55-015a-49b5-a083-c84d1797ae8c { $return = 'Microsoft Intune Enrollment' }
        5b20c633-9a48-4a5f-95f6-dae91879051f { $return = 'Azure Information Protection' }
        441509e5-a165-4363-8ee7-bcf0b7d26739 { $return = 'EnterpriseAgentPlatform' }
        e691bce4-6612-4025-b94c-81372a99f77e { $return = 'Boomerang' }
        8edd93e1-2103-40b4-bd70-6e34e586362d { $return = 'Windows Azure Security Resource Provider' }
        94c63fef-13a3-47bc-8074-75af8c65887a { $return = 'Office Delve' }
        e95d8bee-4725-4f59-910d-94d415da51b9 { $return = 'Skype for Business Name Dictionary Service' }
        e3c5dbcd-bb5f-4bda-b943-adc7a5bbc65e { $return = 'Workflow' }
        8602e328-9b72-4f2d-a4ae-1387d013a2b3 { $return = 'Azure API Management' }
        8b3391f4-af01-4ee8-b4ea-9871b2499735 { $return = 'O365 Secure Score' }
        c26550d6-bc82-4484-82ca-ac1c75308ca3 { $return = 'Office 365 YammerOnOls' }
        33be1cef-03fb-444b-8fd3-08ca1b4d803f { $return = 'OneDrive Web' }
        dcad865d-9257-4521-ad4d-bae3e137b345 { $return = 'Microsoft SharePoint Online - SharePoint Home' }
        b2cc270f-563e-4d8a-af47-f00963a71dcd { $return = 'OneProfile Service' }
        4660504c-45b3-4674-a709-71951a6b0763 { $return = 'Microsoft Invitation Acceptance Portal' }
        ba23cd2a-306c-48f2-9d62-d3ecd372dfe4 { $return = 'OfficeGraph' }
        d52485ee-4609-4f6b-b3a3-68b6f841fa23 { $return = 'On-Premises Data Gateway Connector' }
        996def3d-b36c-4153-8607-a6fd3c01b89f { $return = 's 365 for Financials' }
        b6b84568-6c01-4981-a80f-09da9a20bbed { $return = 'Microsoft Invoicing' }
        9d3e55ba-79e0-4b7c-af50-dc460b81dca1 { $return = 'Microsoft Azure Data Catalog' }
        4345a7b9-9a63-4910-a426-35363201d503 { $return = 'O365 Suite UX' }
        ac815d4a-573b-4174-b38e-46490d19f894 { $return = 'Workflow' }
        bb8f18b0-9c38-48c9-a847-e1ef3af0602d { $return = 'Microsoft.Azure.ActiveDirectoryIUX' }
        cc15fd57-2c6c-4117-a88c-83b1d56b4bbe { $return = 'Microsoft Teams Services' }
        5e3ce6c0-2b1f-4285-8d4b-75ee78787346 { $return = 'Skype Teams' }
        1fec8e78-bce4-4aaf-ab1b-5451cc387264 { $return = 'Microsoft Teams' }
        6d32b7f8-782e-43e0-ac47-aaad9f4eb839 { $return = 'Permission Service O365' }
        cdccd920-384b-4a25-897d-75161a4b74c1 { $return = 'Skype Teams Firehose' }
        1c0ae35a-e2ec-4592-8e08-c40884656fa5 { $return = 'Skype Team Substrate connector' }
        cf6c77f8-914f-4078-baef-e39a5181158b { $return = 'Skype Teams Settings Store' }
        64f79cb9-9c82-4199-b85b-77e35b7dcbcb { $return = 'Microsoft Teams Bots' }
        b7912db9-aa33-4820-9d4f-709830fdd78f { $return = 'ConnectionsService' }
        82f77645-8a66-4745-bcdf-9706824f9ad0 { $return = 'PowerApps Runtime Service' }
        6204c1d1-4712-4c46-a7d9-3ed63d992682 { $return = 'Microsoft Flow Portal' }
        7df0a125-d3be-4c96-aa54-591f83ff541c { $return = 'Microsoft Flow Service' }
        331cc017-5973-4173-b270-f0042fddfd75 { $return = 'PowerAppsService' }
        0a0e9e37-25e3-47d4-964c-5b8237cad19a { $return = 'CloudSponge' }
        df09ff61-2178-45d8-888c-4210c1c7b0b2 { $return = 'O365 UAP Processor' }
        8338dec2-e1b3-48f7-8438-20c30a534458 { $return = 'ViewPoint' }
        00000001-0000-0000-c000-000000000000 { $return = 'Azure ESTS Service' }
        394866fc-eedb-4f01-8536-3ff84b16be2a { $return = 'Microsoft People Cards Service' }
        0a0a29f9-0a25-49c7-94bf-c53c3f8fa69d { $return = 'Cortana Experience with O365' }
        bb2a2e3a-c5e7-4f0a-88e0-8e01fd3fc1f4 { $return = 'CPIM Service' }
        0004c632-673b-4105-9bb6-f3bbd2a927fe { $return = 'PowerApps and Flow' }
        d3ce4cf8-6810-442d-b42e-375e14710095 { $return = 'Graph Explorer' }
        3aa5c166-136f-40eb-9066-33ac63099211 { $return = 'O365 Customer Monitoring' }
        d6fdaa33-e821-4211-83d0-cf74736489e1 { $return = 'Microsoft Service Trust' }
        ef4a2a24-4b4e-4abf-93ba-cc11c5bd442c { $return = 'Edmodo' }
        b692184e-b47f-4706-b352-84b288d2d9ee { $return = 'Microsoft.MileIQ.RESTService' }
        a25dbca8-4e60-48e5-80a2-0664fdb5c9b6 { $return = 'Microsoft.MileIQ' }
        f7069a8d-9edc-4300-b365-ae53c9627fc4 { $return = 'Microsoft.MileIQ.Dashboard' }
        02e3ae74-c151-4bda-b8f0-55fbf341de08 { $return = 'Application Registration Portal' }
        1f5530b3-261a-47a9-b357-ded261e17918 { $return = 'Azure Multi-Factor Auth Connector' }
        981f26a1-7f43-403b-a875-f8b09b8cd720 { $return = 'Azure Multi-Factor Auth Client' }
        6ea8091b-151d-447a-9013-6845b83ba57b { $return = 'AD Hybrid Health' }
        fc68d9e5-1f76-45ef-99aa-214805418498 { $return = 'Azure AD Identity Protection' }
        01fc33a7-78ba-4d2f-a4b7-768e336e890e { $return = 'MS-PIM' }
        a6aa9161-5291-40bb-8c5c-923b567bee3b { $return = 'Storage Resource Provider' }
        4e9b8b9a-1001-4017-8dd1-6e8f25e19d13 { $return = 'Adobe Acrobat' }
        159b90bb-bb28-4568-ad7c-adad6b814a2f { $return = 'LastPass' }
        b4bddae8-ab25-483e-8670-df09b9f1d0ea { $return = 'Signup' }
        aa580612-c342-4ace-9055-8edee43ccb89 { $return = 'Microsoft StaffHub' }
        51133ff5-8e0d-4078-bcca-84fb7f905b64 { $return = 'Microsoft Teams Mailhook' }
        ab3be6b7-f5df-413d-ac2d-abf1e3fd9c0b { $return = 'Microsoft Teams Graph Service' }
        b1379a75-ce5e-4fa3-80c6-89bb39bf646c { $return = 'Microsoft Teams Chat Aggregator' }
        48af08dc-f6d2-435f-b2a7-069abd99c086 { $return = 'Connectors' }
        d676e816-a17b-416b-ac1a-05ad96f43686 { $return = 'Workflow' }
        cfa8b339-82a2-471a-a3c9-0fc0be7a4093 { $return = 'Azure Key Vault' }
        c2f89f53-3971-4e09-8656-18eed74aee10 { $return = 'calendly' }
        6da466b6-1d13-4a2c-97bd-51a99e8d4d74 { $return = 'Exchange Office Graph Client for AAD - Interactive' }
        0eda3b13-ddc9-4c25-b7dd-2f6ea073d6b7 { $return = 'Microsoft Flow CDS Integration Service' }
        eacba838-453c-4d3e-8c6a-eb815d3469a3 { $return = 'Microsoft Flow CDS Integration Service TIP1' }
        4ac7d521-0382-477b-b0f8-7e1d95f85ca2 { $return = 'SQL Server Analysis Services Azure' }
        b4114287-89e4-4209-bd99-b7d4919bcf64 { $return = 'OfficeDelve' }
        4580fd1d-e5a3-4f56-9ad1-aab0e3bf8f76 { $return = 'Call Recorder' }
        a855a166-fd92-4c76-b60d-a791e0762432 { $return = 'Microsoft Teams VSTS' }
        c37c294f-eec8-47d2-b3e2-fc3daa8f77d3 { $return = 'Workflow' }
        fc75330b-179d-49af-87dd-3b1acf6827fa { $return = 'AzureAutomationAADPatchS2S' }
        766d89a4-d6a6-444d-8a5e-e1a18622288a { $return = 'OneDrive' }
        f16c4a38-5aff-4549-8199-ee7d3c5bd8dc { $return = 'Workflow' }
        4c4f550b-42b2-4a16-93f9-fdb9e01bb6ed { $return = 'Targeted Messaging Service' }
        765fe668-04e7-42ba-aec0-2c96f1d8b652 { $return = 'Exchange Office Graph Client for AAD - Noninteractive' }
        0130cc9f-7ac5-4026-bd5f-80a08a54e6d9 { $return = 'Azure Data Warehouse Polybase' }
        a1cf9e0a-fe14-487c-beb9-dd3360921173 { $return = 'Meetup' }
        76cd24bf-a9fc-4344-b1dc-908275de6d6d { $return = 'Azure SQL Virtual Network to Network Resource Provider' }
        9f505dbd-a32c-4685-b1c6-72e4ef704cb0 { $return = 'Amazon Alexa' }
        1e2ca66a-c176-45ea-a877-e87f7231e0ee { $return = 'Microsoft B2B Admin Worker' }
        2634dd23-5e5a-431c-81ca-11710d9079f4 { $return = 'Microsoft Stream Service' }
        cf53fce8-def6-4aeb-8d30-b158e7b1cf83 { $return = 'Microsoft Stream Portal' }
        c9a559d2-7aab-4f13-a6ed-e7e9c52aec87 { $return = 'Microsoft Forms' }
        978877ea-b2d6-458b-80c7-05df932f3723 { $return = 'Microsoft Teams AuditService' }
        dbc36ae1-c097-4df9-8d94-343c3d091a76 { $return = 'Service Encryption' }
        fa7ff576-8e31-4a58-a5e5-780c1cd57caa { $return = 'OneNote' }
        cb4dc29f-0bf4-402a-8b30-7511498ed654 { $return = 'Power BI Premium' }
        f5aeb603-2a64-4f37-b9a8-b544f3542865 { $return = 'Microsoft Teams RetentionHook Service' }
        da109bdd-abda-4c06-8808-4655199420f8 { $return = 'Glip Contacts' }
        76c7f279-7959-468f-8943-3954880e0d8c { $return = 'Azure SQL Managed Instance to Microsoft.Network' }
        3a9ddf38-83f3-4ea1-a33a-ecf934644e2d { $return = 'Protected Message Viewer' }
        5635d99c-c364-4411-90eb-764a511b5fdf { $return = 'Responsive Banner Slider' }
        a43e5392-f48b-46a4-a0f1-098b5eeb4757 { $return = 'Cloudsponge' }
        d73f4b35-55c9-48c7-8b10-651f6f2acb2e { $return = 'MCAPI Authorization Prod' }
        166f1b03-5b19-416f-a94b-1d7aa2d247dc { $return = 'Office Hive' }
        b815ce1c-748f-4b1e-9270-a42c1fa4485a { $return = 'Workflow' }
        bd7b778b-4aa8-4cde-8d90-8aeb821c0bd2 { $return = 'Workflow' }
        9d06afd9-66c9-49a6-b385-ea7509332b0b { $return = 'O365SBRM Service' }
        9ea1ad79-fdb6-4f9a-8bc3-2b70f96e34c7 { $return = 'Bing' }
        57fb890c-0dab-4253-a5e0-7188c88b2bb4 { $return = 'SharePoint Online Client' }
        45c10911-200f-4e27-a666-9e9fca147395 { $return = 'drawio' }
        b73f62d0-210b-4396-a4c5-ea50c4fab79b { $return = 'Skype Business Voice Fraud Detection and Prevention' }
        bc59ab01-8403-45c6-8796-ac3ef710b3e3 { $return = 'Outlook Online Add-in App' }
        035f9e1d-4f00-4419-bf50-bf2d87eb4878 { $return = 'Azure Monitor Restricted' }
        7c33bfcb-8d33-48d6-8e60-dc6404003489 { $return = 'Network Watcher' }
        a0be0c72-870e-46f0-9c49-c98333a996f7 { $return = 'AzureDnsFrontendApp' }
        1e3e4475-288f-4018-a376-df66fd7fac5f { $return = 'NetworkTrafficAnalyticsService' }
        7557eb47-c689-4224-abcf-aef9bd7573df { $return = 'Skype for Business' }
        c39c9bac-9d1f-4dfb-aa29-27f6365e5cb7 { $return = 'Azure Advisor' }
        2087bd82-7206-4c0a-b305-1321a39e5926 { $return = 'Microsoft To-Do' }
        f8d98a96-0999-43f5-8af3-69971c7bb423 { $return = 'iOS Accounts' }
        c27373d3-335f-4b45-8af9-fe81c240d377 { $return = 'P2P Server' }
        5c2ffddc-f1d7-4dc3-926e-3c1bd98e32bd { $return = 'RITS Dev' }
        982bda36-4632-4165-a46a-9863b1bbcf7d { $return = 'O365 Demeter' }
        98c8388a-4e86-424f-a176-d1288462816f { $return = 'OfficeFeedProcessors' }
        bf9fc203-c1ff-4fd4-878b-323642e462ec { $return = 'Jarvis Transaction Service' }
        257601fd-462f-4a21-b623-7f719f0f90f4 { $return = 'Centralized Deployment' }
        2a486b53-dbd2-49c0-a2bc-278bdfc30833 { $return = 'Cortana at Work Service' }
        22d7579f-06c2-4baa-89d2-e844486adb9d { $return = 'Cortana at Work Bing Services' }
        4c8f074c-e32b-4ba7-b072-0f39d71daf51 { $return = 'IPSubstrate' }
        a164aee5-7d0a-46bb-9404-37421d58bdf7 { $return = 'Microsoft Teams AuthSvc' }
        354b5b6d-abd6-4736-9f51-1be80049b91f { $return = 'Microsoft Mobile Application Management Backend' }
        82b293b2-d54d-4d59-9a95-39c1c97954a7 { $return = 'Tasks in a Box' }
        fdc83783-b652-4258-a622-66bc85f1a871 { $return = 'FedExPackageTracking' }
        d0597157-f0ae-4e23-b06c-9e65de434c4f { $return = 'Microsoft Teams Task Service' }
        f5c26e74-f226-4ae8-85f0-b4af0080ac9e { $return = 'Application Insights API' }
        57c0fc58-a83a-41d0-8ae9-08952659bdfd { $return = 'Azure Cosmos DB Virtual Network To Network Resource Provider' }
        744e50be-c4ff-4e90-8061-cd7f1fabac0b { $return = 'LinkedIn Microsoft Graph Connector' }
        823dfde0-1b9a-415a-a35a-1ad34e16dd44 { $return = 'Microsoft Teams Wiki Images Migration' }
        3ab9b3bc-762f-4d62-82f7-7e1d653ce29f { $return = 'Microsoft Volume Licensing' }
        44eb7794-0e11-42b6-800b-dc31874f9f60 { $return = 'Alignable' }
        c58637bb-e2e1-4312-8a00-04b5ffcd3403 { $return = 'SharePoint Online Client Extensibility' }
        62b732f7-fc71-40bc-b27d-35efcb0509de { $return = 'Microsoft Teams AadSync' }
        07978fee-621a-42df-82bb-3eabc6511c26 { $return = 'SurveyMonkey' }
        47ee738b-3f1a-4fc7-ab11-37e4822b007e { $return = 'Azure AD Application Proxy' }
        00000007-0000-0000-c000-000000000000 { $return = 'Dynamics CRM Online' }
        913c6de4-2a4a-4a61-a9ce-945d2b2ce2e0 { $return = 'Dynamics Lifecycle services' }
        f217ad13-46b8-4c5b-b661-876ccdf37302 { $return = 'Attach OneDrive files to Asana' }
        00000008-0000-0000-c000-000000000000 { $return = 'Microsoft.Azure.DataMarket' }
        9b06ebd4-9068-486b-bdd2-dac26b8a5a7a { $return = 'Microsoft.DynamicsMarketing' }
        e8ab36af-d4be-4833-a38b-4d6cf1cfd525 { $return = 'Microsoft Social Engagement' }
        8909aac3-be91-470c-8a0b-ff09d669af91 { $return = 'Microsoft Parature Dynamics CRM' }
        71234da4-b92f-429d-b8ec-6e62652e50d7 { $return = 'Microsoft Customer Engagement Portal' }
        b861dbcc-a7ef-4219-a005-0e4de4ea7dcf { $return = 'Data Export Service for Microsoft Dynamics 365' }
        2db8cb1d-fb6c-450b-ab09-49b6ae35186b { $return = 'Microsoft Dynamics CRM Learning Path' }
        2e49aa60-1bd3-43b6-8ab6-03ada3d9f08b { $return = 'Dynamics Data Integration' }
    }

    if ([string]::IsNullOrEmpty($return)) {
        $return = $Applications | Where-Object { $_.Appid -eq $ID } | Select-Object -ExpandProperty DisplayName 
    }

    if ([string]::IsNullOrEmpty($return)) {
        $return = $Applications | Where-Object { $_.ID -eq $ID } | Select-Object -ExpandProperty DisplayName 
    }

    if ([string]::IsNullOrEmpty($return)) {
        $return = ''
    }

    return $return
}

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
try {
    $ConditionalAccessPolicyOutput = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies" -tenantid $tenantfilter
    $AllNamedLocations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations" -tenantid $tenantfilter
    $AllApplications = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications" -tenantid $tenantfilter
    $AllRoleDefinitions = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleDefinitions" -tenantid $tenantfilter
    $GroupListOutput = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups" -tenantid $tenantfilter
    $UserListOutput = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users" -tenantid $tenantfilter | Select-Object * -ExcludeProperty *extensionAttribute*

    $GraphRequest = foreach ($cap in $ConditionalAccessPolicyOutput) {
        $temp = [PSCustomObject]@{
            id                                          = $cap.id
            displayName                                 = $cap.displayName
            customer                                    = $cap.Customer
            tenantID                                    = $cap.TenantID
            createdDateTime                             = $(if (![string]::IsNullOrEmpty($cap.createdDateTime)) { [datetime]$cap.createdDateTime | Get-Date -Format "yyyy-MM-dd HH:mm" }else { "" })
            modifiedDateTime                            = $(if (![string]::IsNullOrEmpty($cap.modifiedDateTime)) { [datetime]$cap.modifiedDateTime | Get-Date -Format "yyyy-MM-dd HH:mm" }else { "" })
            state                                       = $cap.state
            clientAppTypes                              = ($cap.conditions.clientAppTypes) -join ","
            includePlatforms                            = ($cap.conditions.platforms.includePlatforms) -join ","
            excludePlatforms                            = ($cap.conditions.platforms.excludePlatforms) -join ","
            includeLocations                            = (Get-LocationNameFromId -Locations $AllNamedLocations -id $cap.conditions.locations.includeLocations) -join ","
            excludeLocations                            = (Get-LocationNameFromId -Locations $AllNamedLocations -id $cap.conditions.locations.excludeLocations) -join ","
            includeApplications                         = ($cap.conditions.applications.includeApplications | ForEach-Object { Get-ApplicationNameFromId -Applications $AllApplications -id $_ }) -join ","
            excludeApplications                         = ($cap.conditions.applications.excludeApplications | ForEach-Object { Get-ApplicationNameFromId -Applications $AllApplications -id $_ }) -join ","
            includeUserActions                          = ($cap.conditions.applications.includeUserActions | Out-String)
            includeAuthenticationContextClassReferences = ($cap.conditions.applications.includeAuthenticationContextClassReferences | Out-String)
            includeUsers                                = ($cap.conditions.users.includeUsers | ForEach-Object { Get-UserNameFromId -Users $UserListOutput -id $_ }) | Out-String
            excludeUsers                                = ($cap.conditions.users.excludeUsers | ForEach-Object { Get-UserNameFromId -Users $UserListOutput -id $_ }) | Out-String
            includeGroups                               = ($cap.conditions.users.includeGroups | ForEach-Object { Get-GroupNameFromId -Groups $GroupListOutput -id $_ }) | Out-String
            excludeGroups                               = ($cap.conditions.users.excludeGroups | ForEach-Object { Get-GroupNameFromId -Groups $GroupListOutput -id $_ }) | Out-String
            includeRoles                                = ($cap.conditions.users.includeRoles | ForEach-Object { Get-RoleNameFromId -RoleDefinitions $AllRoleDefinitions -id $_ }) | Out-String
            excludeRoles                                = ($cap.conditions.users.excludeRoles | ForEach-Object { Get-RoleNameFromId -RoleDefinitions $AllRoleDefinitions -id $_ }) | Out-String
            grantControlsOperator                       = ($cap.grantControls.operator) -join ","
            builtInControls                             = ($cap.grantControls.builtInControls) -join ","
            customAuthenticationFactors                 = ($cap.grantControls.customAuthenticationFactors) -join ","
            termsOfUse                                  = ($cap.grantControls.termsOfUse) -join ","
            rawjson                                     = ($cap | ConvertTo-Json -Depth 100)
        }
        $temp
    }
    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })

    }
