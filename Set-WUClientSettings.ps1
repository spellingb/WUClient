<#
.Synopsis
   Configures WSUS on target computers
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
    [CmdletBinding(SupportsShouldProcess, 
                  ConfirmImpact='Medium')]
    [Alias()]
    [OutputType([String])]
    Param
    (
        # Name of computer to connect to. Can be a collection of computers.
        [Parameter(ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias("Computer")] 
        [string[]]$ComputerName=$env:COMPUTERNAME,

        [string]$UpdateServer = "https://wsus.armor.com",

        [ValidateSet('Notify','DownloadOnly','DownloadAndInstall')]
        [string]$AUOption,

        [ValidateSet('EveryDay','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
        [string[]]$ScheduledInstallDay,

        [ValidateRange(0,23)]
        [Int32]$ScheduledInstallTime,

        [ValidateSet('Enable','Disable')]
        [string]$AllowAutomaticUpdates,
        
        [ValidateSet('Enable','Disable')]
        [string]$UseWSUSServer
        
          
    )

    Begin
    {
        Function Set-WUKey($RegKey,[ValidateSet('WU','AU')]$SubKey,$KeyName,$KeyValue)
        {
            $WUKey = Switch($Subkey)
            {
                "WU" {$regkey.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate',$True)}
                "AU" {$regkey.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate\AU',$True)}
            }
            $WUKey.SetValue($KeyName,$KeyValue,[Microsoft.Win32.RegistryValueKind]::String)
        }#Set-WUKey
    }
    Process
    {
        $ErrorActionPreference = 'stop'
        foreach($Computer in $ComputerName)
        {
            try
            {
                #Test connection to remote machine and get the 
                $remoteregistrystatus = (Get-Service -Name RemoteRegistry -ComputerName "$computer").status
                if($remoteregistrystatus -ne 'started')
                {
                    
                    Set-Service -Name RemoteRegistry -ComputerName $computer -StartupType Manual -Status Running
                }
                $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computer)
                $temp = $Reg.OpenSubKey('Software\Policies\Microsoft\Windows',$True)

                If (-NOT ($temp.GetSubKeyNames() -contains 'WindowsUpdate')) 
                {
                    #Build the required registry keys
                    $temp.CreateSubKey('WindowsUpdate\AU') | Out-Null
                }
            }
            catch
            {
                Write-Warning ( "{0}: Unable to communicate to establish Remote Registy Connection." -f $Computer)
                $_
                break
            }

            #Set WU Update Server
            $WSUSEnv = $Reg.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate',$True)
            If ($PSBoundParameters['UpdateServer']) 
            {
                foreach($wukey in @('WUServer','WUStatusServer'))
                {
                    Set-WUKey -RegKey $reg -SubKey WU -KeyName $wukey -KeyValue $UpdateServer
                }
            }#UpdateServer

            #Set WSUS Client Configuration Options
            $WSUSConfig = $Reg.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate\AU',$True)

            If ($PSBoundParameters['AUOption']) 
            {
                $STRauoption = switch($auoption)
                {
                    'Notify'{2}
                    'DownloadOnly'{3}
                    'DownloadAndInstall'{4}
                }
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName AUOptions -KeyValue $STRauoption
            }#AUOption 
            If ($PSBoundParameters['ScheduledInstallDay']) 
            {
                $STRInstallDay = switch($ScheduledInstallDay)
                {
                    'Everyday'{0}
                    'Sunday'{1}
                    'Monday'{2}
                    'Tuesday'{3}
                    'Wednesday'{4}
                    'Thursday'{5}
                    'Friday'{6}
                    'Saturday'{7}
                }
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName ScheduledInstallDay -KeyValue $STRInstallDay
            }#ScheduleInstallDay
            If ($PSBoundParameters['ScheduledInstallTime']) 
            {
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName ScheduledInstallTime -KeyValue $ScheduledInstallTime
            }#ScheduleInstallTime
            If ($PSBoundParameters['AllowAutomaticUpdates']) 
            {
                $strNoAutoUpdate = switch($AllowAutomaticUpdates)
                {
                    'Enable' {1}
                    'Disable' {0}
                }
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName NoAutoUpdate -KeyValue $strNoAutoUpdate
            }#AllowAutomaticUpdates
            If ($PSBoundParameters['UseWSUSServer']) 
            {
                $strUseWUServer = Switch($UseWSUSServer)
                {
                    'Enable' {1}
                    'Disable' {0}
                }
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName UseWUServer -KeyValue $strUseWUServer            
            }#UseWSUSServer

        }#Foreach Computer




    }
    End
    {
    }
