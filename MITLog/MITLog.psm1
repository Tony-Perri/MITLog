<#
    Module for querying the MOVEit Transfer REST API 
    /ap1/v1/logs endpoint.

    Works with MOVEit Transfer 2020.1 and later.

    Make sure to install this file and the MITLog.Format.ps1xml
    in a folder named MITLog in your $Env:PSModulePath path.
#>

# Update the format data to display the Log output and paging info   
Update-FormatData -AppendPath "$PSScriptRoot\MITLog.Format.ps1xml"    

# BaseUri for the MOVEit Transfer server
# Will be set by Get-MITToken
$script:BaseUri = ''

# Variable to hold the current Auth Token.
# Will be set by Get-MITToken
$script:Token = @()

function New-MITToken {
    <#
    .SYNOPSIS
        Create an auth token.
    .DESCRIPTION
        Create an auth token using the /api/v1/token endpoint.
        Call before calling any other Get-MIT* commands.            
    .EXAMPLE
        New-MITToken
        User is prompted for parameters.
    .EXAMPLE
        New-MITToken -Hostname 'moveit.server.com' -Credential (Get-Credential -Username 'admin')
        Supply parameters on command line except for password.
    .INPUTS
        None.
    .OUTPUTS
        String message if connected.
    .LINK
        See link for /api/v1/token doc.
        https://docs.ipswitch.com/MOVEit/Transfer2020/API/rest/#operation/Auth_GetToken
    #>
    [CmdletBinding()]
    param (      
        # Hostname for the endpoint                 
        [Parameter(Mandatory=$true)]
        [string]$Hostname,

        # Credentials
        [Parameter(Mandatory=$true)]
        [pscredential]$Credential
    )     

    # Clear any existing Token
    $script:Token = @()

    # Set the Base Uri
    $script:BaseUri = "https://$Hostname/api/v1"
    
    # Build the request
    $uri = "$script:BaseUri/token"
    $params = @{ 
        Method = 'POST'
        ContentType = 'application/x-www-form-urlencoded'        
        Headers = @{Accept = "application/json"}            
    }
    try {                    
        $response = @{
            grant_type = 'password'
            username = $Credential.UserName
            password= $Credential.GetNetworkCredential().Password
            } | Invoke-RestMethod -Uri $uri @params

        if ($response.access_token) {
            $script:Token = @{                    
                AccessToken = $Response.access_token
                CreatedAt = $(Get-Date)
                ExpiresIn = $Response.expires_in
                RefreshToken = $Response.refresh_token
            }
            Write-Output "New token created for access to $script:BaseUri"
        }
    } 
    catch {
        $_
    }   
}
function Get-MITLog {
    <#
    .SYNOPSIS
        Get MOVEit Transfer logs
    .DESCRIPTION
        Get MOVEit Transfer logs from /api/v1/logs endpoint
        Requires MOVEit Transfer 2020.1 and later
        Call New-MITToken prior to calling this function
    .EXAMPLE
        Get-MITLog -SortDirection desc
        Get logs in descending order
    .EXAMPLE
        Get-MITLog -Action FileTransfer -SortDirection desc
        Get logs in descending order filtered by action
    .EXAMPLE
        Get-MITlog -StartDateTime (Get-Date).AddDays(-1) -SortDirection desc
        Get logs in descending order for past 24 hours
    .EXAMPLE
        # Script to get all log entries since yesterday
        $params = @{
            SortDirection = 'desc'    
            StartDateTime = (Get-Date).Date.AddDays(-1)
            IncludeSigns = $true    
        }
        # Run the query first to determine how many pages
        $totalPages = (Get-MITLog @params)[0].totalPages
        # Retrieve all pages
        1..$totalPages | foreach-object { Get-MITLog @params -Page $_ -NoPagingInfo }                
    .INPUTS
        None
    .OUTPUTS
        Collection of log records as custom MITLog objects
        Paging info as custom MITPaging object
    .LINK
        See link for /api/v1/token doc.
        https://docs.ipswitch.com/MOVEit/Transfer2020_1/API/rest/index.html#tag/Logs
    #>
    [CmdletBinding()]
    param (           
        # switch to not include PagingInfo in the output
        [Parameter(Mandatory=$false)]
        [switch]$NoPagingInfo,

        # startDateTime for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$StartDateTime,
        
        # endDateTime for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$EndDateTime,

        # action for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [ValidateSet('None','FileTransfer','Administration','Upload',
                    'Download','UserMaintenance','ContentScanning')]
        [string]$Action,

        # userNameContains for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$UserNameContains,

        # userId for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$UserId,

        # fileIdContains for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$FileIdContains,

        # fileNameContains for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$FileNameContains,

        # sizeComparison for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [ValidateSet('None','LargerOrEqual','SmallerOrEqual')]
        [string]$SizeComparison,

        # size for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$Size,

        # folderId for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$FolderId,

        # folderPathContains for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$FolderPathContains,
        
        # ipContains for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$IpContains,

        # agentBrandContains for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [string]$AgentBrandContains,

        # successFailure for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [ValidateSet('None', 'Success', 'Error')]
        [string]$SuccessFailure,

        # suppressSigns for REST call
        # Note this switch sets suppressSigns to False
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [switch]$IncludeSigns,

        # suppressEmailNotes for REST call
        # Note this switch sets suppressEmailNotes to False
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [switch]$IncludeEmailNotes,

        # suppressLogViews for REST call
        # Note this switch sets suppressLogViews to False
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [switch]$IncludeLogViews,        
        
        # page for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [int32]$Page,
        
        # perPage for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [int32]$PerPage,

        # sortField for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [ValidateSet('id', 'logtime', 'action', 'username', 'userrealname', 'targetname', 
                    'filename', 'fileid', 'folderpath', 'xfersize', 'duration', 
                    'rate', 'ipaddress', 'agentbrand', 'resilnode')]
        [string]$SortField,
        
        # sortDirection for REST call
        [Parameter(Mandatory=$false, ParameterSetName='List')]
        [ValidateSet('asc', 'desc')]
        [string]$SortDirection
    )
    
    # Check to see if MIT-Token has been called and exit with an error
    # if it hasn't.
    if (-not $script:BaseUri) {
        Write-Error "BaseUri is invalid.  Try calling MIT-Token first."
        return        
    }

    # Set the Uri for this request
    $uri = "$script:BaseUri/logs"
                
    # Set the request headers
    $headers = @{
        Accept = "application/json"
        Authorization = "Bearer $($script:Token.AccessToken)"
    }   

    # Build the query string as an object to pass to the -Body parameter
    $query = @{
        startDateTime = $StartDateTime
        endDateTime = $EndDateTime
        action = $Action
        userNameContains = $UserNameContains
        userId = $UserId
        fileIdContains = $FileIdContains
        fileNameContains = $FileNameContains
        sizeComparison = $SizeComparison
        size = $Size
        folderId = $FolderId
        folderPathContains = $FolderPathContains
        ipContains = $IpContains
        agentBrandContains = $AgentBrandContains
        successFailure = $SuccessFailure
        suppressSigns = if ($IncludeSigns) { "$false" };
        suppressEmailNotes = if ($IncludeEmailNotes) { "$false" };
        suppressLogViews = if ($IncludeLogViews) { "$false" };
        page = $Page
        perPage = $PerPage 
        sortField = $SortField
        sortDirection = $SortDirection                       
    }

    # This will remove keys with no value since it may mess around with some API's.
    # Note, this will also remove values of $false and of 0.                
    @($query.Keys) | where-object { -not $query[$_] } | foreach-object { $query.Remove($_) }

    try {
        # Call the REST Api
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -Body $query

        # Add type and write the paging info.  Want to send this down the pipeline first
        # so the caller can check the first item for this information if they want
        # to loop through multiple pages, etc.
        if ($response.paging -and -not $NoPagingInfo) {
            $response.paging.PSObject.TypeNames.Insert(0,'MITPaging')
            $response.paging 
        }

        # Add type to the items for better display from .format.ps1xml file and write
        # to the pipeline
        if ($response.items) {
            $response.items | foreach-object { $_.PSOBject.TypeNames.Insert(0,'MITLog') }
            $response.items
        }
    }
    catch {        
        $_
    }                  
}