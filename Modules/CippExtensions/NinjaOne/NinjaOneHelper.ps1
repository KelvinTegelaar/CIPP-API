function Get-NinjaOneTitle($Title, $Icon, $TitleLink, $TitleSize, $TitleClass) {
    Return $(if ($TitleSize) { '<' + $TitleSize + ' style="font-family: sans-serif"' }else { '<span style="font-family: sans-serif"' }) + $(if ($TitleClass) { ' class="' + $TitleClass + '"' }) + '>' + $(if ($Icon) { '<i class="' + $Icon + '"></i>&nbsp;&nbsp;' }) + $Title + $(if ($TitleLink) { '&nbsp;&nbsp;<a href="' + $TitleLink + '" target="_blank" class="text-decoration-none"><i class="fas fa-arrow-up-right-from-square fa-2xs" style="color: #337ab7;"></i></a>' }) + $(if ($TitleSize) { "</$TitleSize>" }else { '</span>' })
}

### HTML Formatters ###
# Bar Graph
function Get-NinjaInLineBarGraph ($Data, [string]$Title, [string]$Icon, [string]$TitleLink, [switch]$KeyInLine, [switch]$NoCount, [switch]$NoSort) {
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

    if (!$NoSort) {
        $Data = $Data | Sort-Object Amount -Descending
    }

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
        $OutputHTML.add('<ul class="list-unstyled p-3" style="display: flex; justify-content: space-between; font-family: sans-serif;" list-style-type: none;>')
    } else {
        $OutputHTML.add('<ul class="list-unstyled p-3" style="font-family: sans-serif; list-style-type: none;">')
    }

    foreach ($Item in $Data) {
        $OutputHTML.add(@"
        <li><span style="display: inline-block; width: 20px; height: 20px; background-color: $($Item.Colour); margin-right: 10px;"></span><span style="font-family: sans-serif;"> $($Item.Label) ($($Item.Amount))</span></li>
"@)

    }

    $OutputHTML.add('</ul>')

    return $OutputHTML -join ''


}

#### List of Links
function Get-NinjaOneLinks ($Data, $Title, [string]$Icon, [string]$TitleLink, [int]$SmallCols, [int]$MedCols, [int]$LargeCols, [int]$XLCols) {
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

    $OutputHTML.add('<div class="card" style="padding:10px; margin:10px; margin-right:20px; font-family: sans-serif;">')

    if ($Title) {
        $OutputHTML.add('<div class="card-title-box"><div class="card-title" style="font-family: sans-serif;">' + $(if ($Icon) { '<i class="' + $Icon + '"></i>&nbsp;&nbsp;' }) + $Title + '</div>')

        if ($TitleLink) {
            $OutputHTML.add('<div class="card-link-box"><a href="' + $TitleLink + '" target="_blank" class="card-link" style="font-family: sans-serif;"><i class="fas fa-arrow-up-right-from-square" style="color: #337ab7;"></i></a></div>')
        }

        $OutputHTML.add('</div>')
    }

    $OutputHTML.add('<div class="row" style="justify-content: center; font-family: sans-serif; width: 100%;">')

    $CSSCols = Get-NinjaOneCSSCol -SmallCols $SmallCols -MedCols $MedCols -LargeCols $LargeCols -XLCols $XLCols

   
    foreach ($Item in $Data) {


        $OutputHTML.add(@"
        <div class="$CSSCols" style="margin-bottom: 24px;"><a href="$($Item.Link)" class="btn secondary" target="_blank" style="margin: 10px; font-family: sans-serif; width: 100%; height: 100%;">$(if ($Item.Icon){"<span><i class=`"$($Item.Icon)`"></i>&nbsp;&nbsp;</span>"})<span style="text-align: center;">$($Item.Name)</span></a></div>
"@)

    }

    $OutputHTML.add('</div></div>')

    return $OutputHTML -join ''

}


function Get-NinjaOneWidgetCard($Title, $Data, [string]$Icon, [string]$TitleLink, [int]$SmallCols, [int]$MedCols, [int]$LargeCols, [int]$XLCols, [Switch]$NoCard) {
    <#
    $Data = @(
        @{
            Value = 20
            Description = 'Users'
            Colour = '#CCCCCC'
            Link = 'https://example.com/users'
        },
        @{
            Value = 42
            Description = 'Devices'
            Colour = '#CCCCCC'
            Link = 'https://example.com/devices'
        }
    )
    
    $HTML = Get-NinjaOneWidgetCard -Title 'Summary Details' -Data $Data -Icon 'fas fa-building' -TitleLink 'http://example.com' -Columns 3

    #>

    $CSSCols = Get-NinjaOneCSSCol -SmallCols $SmallCols -MedCols $MedCols -LargeCols $LargeCols -XLCols $XLCols


    [System.Collections.Generic.List[String]]$OutputHTML = @()
    
    $OutputHTML.add('<div class="row" style="justify-content: center; align-items: center; width:100%;">')


    foreach ($Item in $Data) {

        $HTML = @"
    <div class="$CSSCols">
        <div class="card" style="justify-content: center; align-items: center; margin: 0px; padding-top: 36px; padding-bottom: 36px; text-align: Center; margin-bottom: 24px; height:148px;">
            <div class="row" style="height: 50%"><a href="$($Item.Link)" target="_blank" style="text-decoration: none;"><span style="font-size: 40px; color: $($Item.Colour); margin-bottom: 10px;">$($Item.Value)</span></a></div>
            <div class="row" style="height: 50%"><a href="$($Item.Link)" target="_blank" style="text-decoration: none;"><span style="font-size: 18px;"><span style="white-space:nowrap;">$($Item.Description -replace " ",'</span>&nbsp;<span style="white-space:nowrap;">')</span></span></a></div>
        </div>
    </div>
"@

        $OutputHTML.add($HTML)

    }

    $OutputHTML.add('</div>')

    if ($NoCard) {
        return $OutputHTML -join ''
    } else {
        Return Get-NinjaOneCard -Title $Title -Body ($OutputHTML -join '') -Icon $Icon -TitleLink $TitleLink
    }

}

Function Get-NinjaOneCSSCol($SmallCols, $MedCols, $LargeCols, $XLCols) {
    $SmallCSS = "col-sm-$([Math]::Floor(12 / $SmallCols))"
    $MediumCSS = "col-md-$([Math]::Floor(12 / $MedCols))"
    $LargeCSS = "col-lg-$([Math]::Floor(12 / $LargeCols))"
    $XLCSS = "col-xl-$([Math]::Floor(12 / $XLCols))"

    Return "$SmallCSS $MediumCSS $LargeCSS $XLCSS"
}

function Get-NinjaOneCard($Title, $Body, [string]$Icon, [string]$TitleLink, [String]$Classes) {
    <#
    $Info = 'This is the body of a card it is wrapped in a paragraph'

    Get-NinjaOneCard -Title "Tenant Details" -Data $Info
    #>

    [System.Collections.Generic.List[String]]$OutputHTML = @()

    $OutputHTML.add('<div class="card' + $(if ($classes) { ' ' + $classes }) + '" >')

    if ($Title) {
        $OutputHTML.add('<div class="card-title-box"><div class="card-title" style="font-family: sans-serif;">' + $(if ($Icon) { '<i class="' + $Icon + '"></i>&nbsp;&nbsp;' }) + $Title + '</div>')

        if ($TitleLink) {
            $OutputHTML.add('<div class="card-link-box"><a href="' + $TitleLink + '" target="_blank" class="card-link" style="font-family: sans-serif;"><i class="fas fa-arrow-up-right-from-square" style="color: #337ab7;"></i></a></div>')
        }

        $OutputHTML.add('</div>')
    }

    $OutputHTML.add('<div class="card-body" style="font-family: sans-serif;">')
    $OutputHTML.add('<p class="card-text" style="font-family: sans-serif;">' + $Body + '</p>')
       
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
        $ItemsHTML.add('<p style="font-family: sans-serif;"><b style="font-family: sans-serif;">' + $Item.Name + '</b><br />' + $Item.Value + '</p>')
    }

    return Get-NinjaOneCard -Title $Title -Body ($ItemsHTML -join '') -Icon $Icon -TitleLink $TitleLink
       
}

