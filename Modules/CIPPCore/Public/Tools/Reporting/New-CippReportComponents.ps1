#
# Report component builders - the PowerShell authoring layer for server-side reports.
#
# Each function returns one declarative component node (a hashtable) that the CIPPSharp component kit
# renders (see ConvertTo-CippReportPdf / [CIPP.Reporting.ReportPdf]). A report is composed of these
# and never hand-writes OfficeIMO or block JSON: gather data, map it to components, hand the array to
# ConvertTo-CippReportPdf. The node shapes mirror the block types the kit understands
# (page/blank/scorecard/richtable/richbullets/chart/infobox/alertbox/clearbox/hero/pagebreak).
#

function New-CippReportPage {
    # Opens a titled content page (a fixed report's ContentPage): its own header title + subtitle.
    param([Parameter(Mandatory)][string]$Title, [string]$Subtitle)
    $n = [ordered]@{ type = 'page'; title = $Title }
    if ($Subtitle) { $n.subtitle = $Subtitle }
    $n
}

function New-CippReportPageBreak {
    @{ type = 'pagebreak' }
}

function New-CippReportHeading {
    # A section heading on its own (renders the section title, no body).
    param([Parameter(Mandatory)][string]$Title)
    [ordered]@{ type = 'blank'; title = $Title; content = '' }
}

function New-CippReportParagraph {
    # Body copy. -Html passes raw HTML (bold/links); -Text wraps plain text.
    # -Title adds a section heading above the paragraph. -Indent steps plain -Text in under a heading.
    param([string]$Text, [string]$Html, [string]$Title, [switch]$Indent)
    if ($Indent) {
        $n = [ordered]@{ type = 'paragraphindent'; content = [string]$Text }
        if ($Title) { $n.title = $Title }
        return $n
    }
    if ($Html) {
        $n = [ordered]@{ type = 'blank'; content = $Html }
    } else {
        $n = [ordered]@{ type = 'blank'; content = ('<p>{0}</p>' -f [System.Net.WebUtility]::HtmlEncode([string]$Text)) }
    }
    if ($Title) { $n.title = $Title }
    $n
}

function New-CippReportStatRow {
    # A row of stat cards. -Stats: @( @{ value; label; caption; colour }, ... ). An empty row renders nothing.
    param([string]$Title, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Stats)
    $n = [ordered]@{ type = 'scorecard'; stats = @($Stats) }
    if ($Title) { $n.title = $Title }
    $n
}

function New-CippReportTable {
    # A data table. -Columns: @( @{ header; key; width; bold; align; toneField }, ... ). -Rows: row objects.
    # -EmptyText is drawn inside the table border when there are no rows (client DataTable emptyText).
    param([string]$Title, [Parameter(Mandatory)][object[]]$Columns, [object[]]$Rows = @(), [int]$Limit = 25, [string]$EmptyText)
    $n = [ordered]@{ type = 'richtable'; columns = @($Columns); rows = @($Rows); limit = $Limit }
    if ($Title) { $n.title = $Title }
    if ($EmptyText) { $n.emptyText = $EmptyText }
    $n
}

function New-CippReportBullets {
    # Rich bullets. -Items: @( @{ label; text }, ... ) (label is optional bold prefix).
    param([string]$Title, [Parameter(Mandatory)][object[]]$Items)
    $n = [ordered]@{ type = 'richbullets'; items = @($Items) }
    if ($Title) { $n.title = $Title }
    $n
}

function New-CippReportNote {
    # A small italic aside (client Note / truncation line): "... and N more".
    param([Parameter(Mandatory)][string]$Text)
    [ordered]@{ type = 'note'; content = $Text }
}

function New-CippReportChart {
    # A chart: -Kind bar|donut|trend, -Data @( @{ label; value; colour }, ... ). Title shows in the frame.
    # Empty data is allowed: the kit draws a "No data available" frame (a tenant with no mail, no risks...).
    param([string]$Title, [ValidateSet('bar', 'donut', 'trend')][string]$Kind = 'bar', [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Data, [double]$Max, [string]$Caption, [string]$CentreLabel)
    $n = [ordered]@{ type = 'chart'; chartKind = $Kind; chartData = @($Data) }
    if ($Title) { $n.title = $Title }
    if ($PSBoundParameters.ContainsKey('Max')) { $n.max = $Max }
    if ($Caption) { $n.caption = $Caption }
    if ($CentreLabel) { $n.centreLabel = $CentreLabel }
    $n
}

function New-CippReportProgress {
    # A list of labelled progress bars (the client ProgressList). -Items: @( @{ label; value; max; display; colour }, ... ).
    # Each renders a value/max data bar over a grey track - zero-safe (a 0 value draws an empty track), unlike a
    # bar chart whose rounded bars collapse at zero. -Display overrides the "N%" label (e.g. a raw count).
    param([string]$Title, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items)
    $n = [ordered]@{ type = 'progress'; items = @($Items) }
    if ($Title) { $n.title = $Title }
    $n
}

function New-CippReportInfoBox {
    # A callout with a left accent stripe. -Tone ok|warn tints it; -Content is markdown, unless -Lines is
    # set, in which case each '\n' line is kept as a tight line break (label/value detail lists).
    param([Parameter(Mandatory)][string]$Title, [string]$Content, [ValidateSet('', 'ok', 'warn')][string]$Tone = '', [string]$Colour, [switch]$TintTitle, [switch]$Lines)
    $n = [ordered]@{ type = 'infobox'; title = $Title; content = $Content }
    if ($Tone) { $n.tone = $Tone }
    if ($Colour) { $n.colour = $Colour }
    if ($TintTitle) { $n.tintTitle = $true }
    if ($Lines) { $n.lines = $true }
    $n
}

function New-CippReportInfoBoxColumns {
    # A grid of callouts laid out -Columns per row (client Columns of InfoBoxes). -Items:
    # @( @{ title; content; colour; tone; tintTitle }, ... ). Content is plain prose.
    param([Parameter(Mandatory)][object[]]$Items, [int]$Columns = 2)
    [ordered]@{ type = 'infoboxcolumns'; items = @($Items); columns = $Columns }
}

function New-CippReportAlertBox {
    # A warning callout. -Content is markdown, unless -Lines keeps each '\n' line as a tight line break.
    param([Parameter(Mandatory)][string]$Title, [string]$Content, [string]$Colour, [switch]$Lines)
    $n = [ordered]@{ type = 'alertbox'; title = $Title; content = $Content }
    if ($Colour) { $n.colour = $Colour }
    if ($Lines) { $n.lines = $true }
    $n
}

function New-CippReportClearBox {
    param([Parameter(Mandatory)][string]$Title, [string]$Content, [switch]$Lines)
    $n = [ordered]@{ type = 'clearbox'; title = $Title; content = $Content }
    if ($Lines) { $n.lines = $true }
    $n
}

function New-CippReportHero {
    # A full-bleed chapter divider. -Image is a data-URL cover photo; the big -Highlight sits over it.
    param([string]$Image, [string]$Overtitle, [string]$Highlight, [string]$Headline, [string]$SubText, [string]$FooterText)
    $n = [ordered]@{ type = 'hero' }
    if ($Image) { $n.heroImage = $Image }
    if ($Overtitle) { $n.overtitle = $Overtitle }
    if ($Highlight) { $n.highlight = $Highlight }
    if ($Headline) { $n.headline = $Headline }
    if ($SubText) { $n.subText = $SubText }
    if ($FooterText) { $n.footerText = $FooterText }
    $n
}

function New-CippReportSankey {
    # A flow diagram (the dashboard CippSankey). -Nodes: @( @{ id; nodeColor; label }, ... ) - nodeColor
    # accepts hex or hsl(); -Links: @( @{ source; target; value }, ... ) referencing node ids. Node columns
    # and heights are derived from the link flow. -Height sets the plot height (default 240pt). Empty data
    # draws a "No data available" frame.
    param([string]$Title, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Nodes,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Links, [string]$Caption, [double]$Height)
    $n = [ordered]@{ type = 'sankey'; nodes = @($Nodes); links = @($Links) }
    if ($Title) { $n.title = $Title }
    if ($Caption) { $n.caption = $Caption }
    if ($PSBoundParameters.ContainsKey('Height')) { $n.height = $Height }
    $n
}
