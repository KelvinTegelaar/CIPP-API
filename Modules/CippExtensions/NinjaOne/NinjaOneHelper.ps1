function Get-NinjaOneTitle($Title, $Icon, $TitleLink, $TitleSize, $TitleClass) {
    Return $(if ($TitleSize) { "<$TitleSize" }else { '<h5' }) + $(if ($TitleClass) { ' class="' + $TitleClass + '"' }) + '>' + $(if ($Icon) { '<i class="' + $Icon + '"></i>&nbsp;&nbsp;' }) + $Title + $(if ($TitleLink) { '&nbsp;&nbsp;<a href="' + $TitleLink + '" target="_blank" class="text-decoration-none"><i class="fas fa-arrow-up-right-from-square fa-2xs" style="color: #337ab7;"></i></a>' }) + $(if ($TitleSize) { "</$TitleSize>" }else { '</h5>' })
}

### HTML Formatters ###
# Bar Graph
function Get-NinjaInLineBarGraph ($Data, [string]$Title, [string]$Icon, [string]$TitleLink, [switch]$KeyInLine, [switch]$NoCount) {
    <# 
    Example: 
    $Data = @(
        @{
            Label = 'Licensed'
            Amount = 3
            Colour = '#55ACBF'
        },
        @{
            Label = 'Unlicensed'
            Amount = 1
            Colour = '#3633B7'
        },
        @{
            Label = 'Guests'
            Amount = 10
            Colour = '#8063BF'
        }
    )
    
    Get-NinjaInLineBarGraph -Title "Users" -Data $Data -KeyInLine

    #>

    $Data = $Data | Sort-Object Amount -Descending

    $Total = ($Data.Amount | measure-object -sum).sum
    [System.Collections.Generic.List[String]]$OutputHTML = @()

    if ($Title) {
        $OutputHTML.add((Get-NinjaOneTitle -Icon $Icon -Title ($Title + $(if (!$NoCount) { " ($Total)" })) -TitleLink $TitleLink))
    }

    $OutputHTML.add('<div class="p-3" style="width: 100%; height: 50px; display: flex;">')

    foreach ($Item in $Data) {
        $OutputHTML.add(@"
        <div style="width: $(($Item.Amount / $Total) * 100)%; background-color: $($Item.Colour);"></div>
"@)

    }

    $OutputHTML.add('</div>')

    if ($KeyInline) {
        $OutputHTML.add('<ul class="list-unstyled p-3" style="display: flex; justify-content: space-between; font-family: sans-serif;">')
    } else {
        $OutputHTML.add('<ul class="list-unstyled p-3" style="font-family: sans-serif">')
    }

    foreach ($Item in $Data) {
        $OutputHTML.add(@"
        <li><span style="display: inline-block; width: 20px; height: 20px; background-color: $($Item.Colour); margin-right: 10px; font-family: sans-serif;"></span>$($Item.Label) ($($Item.Amount))</li>
"@)

    }

    $OutputHTML.add('</ul>')

    return $OutputHTML -join ''


}

#### List of Links
function Get-NinjaOneLinks ($Data, $Title, [string]$Icon, [string]$TitleLink) {
    <#
$ManagementLinksData = @(
        @{
            Name = 'M365 Admin Portal'
            Link = "https://portal.office.com/Partner/BeginClientSession.aspx?CTID=$($customer.CustomerId)&CSDEST=o365admincenter"
            Icon = 'fas fa-cogs'
        },
        @{
            Name = 'Exchange Admin Portal'
            Link = "https://outlook.office365.com/ecp/?rfr=Admin_o365&exsvurl=1&delegatedOrg=$($Customer.DefaultDomainName)"
            Icon = 'fas fa-mail-bulk'
        },
        @{
            Name = 'Entra Admin'
            Link = "https://aad.portal.azure.com/$($Customer.DefaultDomainName)"
            Icon = 'fas fa-users-cog'
        })

        Get-NinjaOneLinks -Title 'M365 Admin Links' -Data $ManagementLinksData
#>

    [System.Collections.Generic.List[String]]$OutputHTML = @()

    $OutputHTML.add('<div class="card" style="padding:10px; margin:10px; margin-right:20px; font-family: sans-serif;"><div class="row" style="justify-content: center; font-family: sans-serif;">')

    if ($Title) {
        $OutputHTML.add((Get-NinjaOneTitle -Icon $Icon -Title $Title -TitleLink $TitleLink))
    }

    foreach ($Item in $Data) {
        $OutputHTML.add(@"
        <a href="$($Item.Link)" class="col-lg-2 col-md-4 col-sm-12 btn secondary" target="_blank" style="margin: 10px; font-family: sans-serif;">$(if ($Item.Icon){"<i class=`"$($Item.Icon)`"></i>&nbsp;&nbsp;"})$($Item.Name)</a>
"@)


    }

    $OutputHTML.add('</div></div>')

    return $OutputHTML -join ''

}

function Get-NinjaOneCard($Title, $Body, [string]$Icon, [string]$TitleLink) {
    <#
    $Info = 'This is the body of a card it is wrapped in a paragraph'

    Get-NinjaOneCard -Title "Tenant Details" -Data $Info
    #>

    [System.Collections.Generic.List[String]]$OutputHTML = @()

    $OutputHTML.add('<div class="card"> <div class="card-body" style="font-family: sans-serif>')

    if ($Title) {
        $OutputHTML.add((Get-NinjaOneTitle -Icon $Icon -Title $Title -TitleLink $TitleLink -TitleSize 'h4' -TitleClass 'card-title'))
    }

    $OutputHTML.add('<p class="card-text" style="font-family: sans-serif>' + $Body + '</p>')
       
    $OutputHTML.add('</div></div>')

    return $OutputHTML -join ''
    
}

function Get-NinjaOneInfoCard($Title, $Data, [string]$Icon, [string]$TitleLink) {
    <#
    $TenantDetailsItems = [PSCustomObject]@{
        'Name' = $Customer.displayName
        'Default Domain' = $Customer.defaultDomainName
        'Tenant ID' = $Customer.customerId
        'Domains' = $customerDomains
        'Admin Users' = ($AdminUsers | ForEach-Object {"$($_.displayname) ($($_.userPrincipalName))"}) -join ', '
        'Creation Date' = $TenantDetails.createdDateTime
    }

    Get-NinjaOneInfoCard -Title "Tenant Details" -Data $TenantDetailsItems
    #>

    [System.Collections.Generic.List[String]]$ItemsHTML = @()

    foreach ($Item in $Data.PSObject.Properties) {
        $ItemsHTML.add('<p style="font-family: sans-serif"><strong>' + $Item.Name + '</strong><br />' + $Item.Value + '</p>')
    }

    return Get-NinjaOneCard -Title $Title -Body ($ItemsHTML -join '') -Icon $Icon -TitleLink $TitleLink
       
    
}
