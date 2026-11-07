# EMYDPI arayüzü (WPF). Tüm işlemleri emydpi.ps1'e yaptırır; burada sadece görünüm var.
# https://github.com/yigitislamoglu/EMYDPI  (MIT)
param([switch]$NoElevate)

$ErrorActionPreference = 'Stop'
$Version = '1.3.0'
$Dir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Main    = Join-Path $Dir 'emydpi.ps1'
$LogFile = Join-Path $Dir 'emydpi.log'
$Repo    = 'https://github.com/yigitislamoglu/EMYDPI'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    # hosts ve zamanlanmis gorev icin yonetici izni gerekli
    Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`""
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="EMYDPI" Width="560" SizeToContent="Height" WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="CanMinimize"
        FontFamily="Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg"      Color="#14161F"/>
    <SolidColorBrush x:Key="Card"    Color="#1C1F2E"/>
    <SolidColorBrush x:Key="Line"    Color="#2B2E45"/>
    <SolidColorBrush x:Key="Text"    Color="#E6E8FF"/>
    <SolidColorBrush x:Key="Muted"   Color="#9AA0C8"/>
    <SolidColorBrush x:Key="Accent"  Color="#5865F2"/>
    <SolidColorBrush x:Key="Green"   Color="#3BA55D"/>
    <SolidColorBrush x:Key="Red"     Color="#ED4245"/>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#2A2E45"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Height" Value="42"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Pill" TargetType="ToggleButton">
      <Setter Property="Foreground" Value="#C9CDF0"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="b" Background="#23263A" BorderBrush="#3A3E5C" BorderThickness="1" CornerRadius="17" Padding="16,7">
              <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="tick" Text="✓ " Visibility="Collapsed" Foreground="#FFFFFF"/>
                <ContentPresenter/>
              </StackPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#5865F2"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#5865F2"/>
                <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Chrome" TargetType="Button">
      <Setter Property="Foreground" Value="#9AA0C8"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Width" Value="34"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#2A2E45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#9AA0C8"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style x:Key="Val" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#E6E8FF"/>
      <Setter Property="FontSize" Value="13"/>
    </Style>
  </Window.Resources>

  <Border Background="{StaticResource Bg}" CornerRadius="16" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="10">
    <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
    <StackPanel Margin="22,14,22,18">

      <!-- baslik -->
      <Grid x:Name="TitleBar" Background="Transparent" Margin="0,0,0,4">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Border Background="{StaticResource Accent}" CornerRadius="9" Width="34" Height="34" Margin="0,0,12,0">
            <TextBlock Text="E" Foreground="White" FontSize="20" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="EMYDPI" Foreground="White" FontSize="20" FontWeight="Bold"/>
              <Border Background="#2A2E45" CornerRadius="6" Padding="7,1" Margin="8,3,0,0" VerticalAlignment="Center">
                <TextBlock x:Name="VerText" Foreground="#AAB2FF" FontSize="11" FontWeight="SemiBold"/>
              </Border>
            </StackPanel>
            <TextBlock Text="Türkiye'de Discord ve Roblox'a tek tıkla erişim" Foreground="{StaticResource Muted}" FontSize="12"/>
          </StackPanel>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
          <Button x:Name="MinBtn" Style="{StaticResource Chrome}" Content="—"/>
          <Button x:Name="CloseBtn" Style="{StaticResource Chrome}" Content="✕"/>
        </StackPanel>
      </Grid>

      <!-- durum -->
      <Border Background="{StaticResource Card}" CornerRadius="12" Padding="18,16" Margin="0,14,0,0">
        <StackPanel>
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="StateDot" Width="14" Height="14" Fill="#9AA0C8" VerticalAlignment="Center"/>
            <TextBlock x:Name="StateText" Text="Durum okunuyor..." Foreground="White" FontSize="18" FontWeight="SemiBold" Margin="10,0,0,0"/>
          </StackPanel>
          <TextBlock x:Name="StateSub" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="24,3,0,0" TextWrapping="Wrap"/>
          <Grid Margin="0,14,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
            <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,8"><TextBlock Text="SERVİSLER" Style="{StaticResource Label}" Margin="0,0,0,2"/><TextBlock x:Name="SvcVal" Text="-" Style="{StaticResource Val}"/></StackPanel>
            <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,0,0,8"><TextBlock Text="PROXY" Style="{StaticResource Label}" Margin="0,0,0,2"/><TextBlock x:Name="ProxyVal" Text="-" Style="{StaticResource Val}"/></StackPanel>
            <StackPanel Grid.Row="1" Grid.Column="0"><TextBlock Text="OTOMATİK BAŞLATMA" Style="{StaticResource Label}" Margin="0,0,0,2"/><TextBlock x:Name="TaskVal" Text="-" Style="{StaticResource Val}"/></StackPanel>
            <StackPanel Grid.Row="1" Grid.Column="1"><TextBlock Text="YÖNTEM" Style="{StaticResource Label}" Margin="0,0,0,2"/><TextBlock x:Name="ModeVal" Text="-" Style="{StaticResource Val}"/></StackPanel>
          </Grid>
          <Border x:Name="ConflictBox" Visibility="Collapsed" Background="#3A1D22" BorderBrush="#ED4245" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,12,0,0">
            <TextBlock x:Name="ConflictText" Foreground="#FFB3B4" FontSize="12.5" TextWrapping="Wrap"/>
          </Border>
        </StackPanel>
      </Border>

      <!-- servisler -->
      <TextBlock Text="HANGİ SERVİSLER?" Style="{StaticResource Label}" Margin="2,18,0,8"/>
      <StackPanel Orientation="Horizontal">
        <CheckBox x:Name="CbDiscord" Content="Discord" Style="{StaticResource Pill}" IsChecked="True"/>
        <CheckBox x:Name="CbRoblox"  Content="Roblox"  Style="{StaticResource Pill}" IsChecked="True"/>
      </StackPanel>

      <!-- ana butonlar -->
      <Button x:Name="InstallBtn" Style="{StaticResource Btn}" Background="{StaticResource Accent}" Height="50" FontSize="16" Margin="0,18,0,0" Content="Kur / Onar"/>
      <Grid Margin="0,10,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition/></Grid.ColumnDefinitions>
        <Button x:Name="StartBtn"     Grid.Column="0" Style="{StaticResource Btn}" Content="▶  Başlat"/>
        <Button x:Name="StopBtn"      Grid.Column="2" Style="{StaticResource Btn}" Content="■  Durdur"/>
        <Button x:Name="UninstallBtn" Grid.Column="4" Style="{StaticResource Btn}" Background="#3A1D22" Foreground="#FF8A8C" Content="Kaldır"/>
      </Grid>

      <!-- gelismis -->
      <ToggleButton x:Name="AdvToggle" Margin="0,16,0,0" Cursor="Hand" HorizontalAlignment="Left">
        <ToggleButton.Template>
          <ControlTemplate TargetType="ToggleButton">
            <TextBlock x:Name="t" Text="Gelişmiş ayarlar ▾" Foreground="#9AA0C8" FontSize="13" FontWeight="SemiBold"/>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True"><Setter TargetName="t" Property="Text" Value="Gelişmiş ayarlar ▴"/></Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Foreground" Value="#E6E8FF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </ToggleButton.Template>
      </ToggleButton>
      <Border x:Name="AdvPanel" Visibility="Collapsed" Background="{StaticResource Card}" CornerRadius="12" Padding="16,14" Margin="0,10,0,0">
        <StackPanel>
          <TextBlock Text="ATLATMA YÖNTEMİ" Style="{StaticResource Label}"/>
          <WrapPanel x:Name="ModePanel">
            <RadioButton x:Name="RbAuto"    GroupName="m" Tag="auto"    Content="Otomatik" Style="{StaticResource Pill}" IsChecked="True" Margin="0,0,8,8"/>
            <RadioButton x:Name="RbTlsrec"  GroupName="m" Tag="tlsrec"  Content="tlsrec"  Style="{StaticResource Pill}" Margin="0,0,8,8"/>
            <RadioButton x:Name="RbMulti"   GroupName="m" Tag="multi"   Content="multi"   Style="{StaticResource Pill}" Margin="0,0,8,8"/>
            <RadioButton x:Name="RbRecfrag" GroupName="m" Tag="recfrag" Content="recfrag" Style="{StaticResource Pill}" Margin="0,0,8,8"/>
            <RadioButton x:Name="RbFrag"    GroupName="m" Tag="frag"    Content="frag"    Style="{StaticResource Pill}" Margin="0,0,8,8"/>
          </WrapPanel>
          <TextBlock Foreground="{StaticResource Muted}" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,12"
                     Text="Otomatik mod operatörüne uyan yöntemi kendisi bulur. Elle seçim sadece sorun giderme içindir. Değişiklik 'Kur / Onar' ile uygulanır."/>
          <StackPanel Orientation="Horizontal">
            <Button x:Name="LogBtn"    Style="{StaticResource Btn}" Height="34" FontSize="13" Padding="0" Width="130" Content="Logu göster"/>
            <Button x:Name="FolderBtn" Style="{StaticResource Btn}" Height="34" FontSize="13" Width="130" Margin="10,0,0,0" Content="Klasörü aç"/>
          </StackPanel>
        </StackPanel>
      </Border>

      <!-- cikti -->
      <Border Background="#0E1017" CornerRadius="12" Margin="0,16,0,0" Padding="14,10" BorderBrush="{StaticResource Line}" BorderThickness="1">
        <ScrollViewer x:Name="OutScroll" Height="115" VerticalScrollBarVisibility="Hidden">
          <TextBlock x:Name="OutText" FontFamily="Consolas" FontSize="12" Foreground="#5C6290" TextWrapping="Wrap" Text="Yapılan işlemler burada görünür."/>
        </ScrollViewer>
      </Border>

      <!-- alt -->
      <Grid Margin="2,12,2,0">
        <TextBlock x:Name="RepoLink" Text="github.com/yigitislamoglu/EMYDPI" Foreground="#7C82A8" FontSize="12" Cursor="Hand"/>
        <TextBlock x:Name="BusyText" HorizontalAlignment="Right" Foreground="#AAB2FF" FontSize="12"/>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1
    $ui[$n.Value] = $win.FindName($n.Value)
}
$ui.VerText.Text = "v$Version"
$script:outEmpty = $true

function Brush([string]$hex) { New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)) }

# ---------------- cikti paneli ----------------
function Add-Out([string]$line) {
    $t = $line.TrimEnd()
    if (-not $t) { return }
    if ($script:outEmpty) { $ui.OutText.Text = ''; $script:outEmpty = $false }
    $color = '#9AA0C8'
    if ($t -match '^\s*\[\+\]') { $color = '#7FD99A' }
    elseif ($t -match '^\s*\[!\]') { $color = '#FF8A8C' }
    elseif ($t -match '^\s*\[i\]') { $color = '#F0C674' }
    elseif ($t -match '^\s*>') { $color = '#FFFFFF' }
    $run = New-Object Windows.Documents.Run ($t.Trim() + "`n")
    $run.Foreground = Brush $color
    $ui.OutText.Inlines.Add($run)
    $ui.OutScroll.ScrollToEnd()
}

# ---------------- arka planda emydpi.ps1 calistirma ----------------
# UI donmasin diye: islem ciktisi gecici dosyaya yazilir, zamanlayici okuyup panele ekler
$script:job = $null
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)

function Read-New($j) {
    try {
        $fs = [IO.File]::Open($j.Out, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -le $j.Pos) { return '' }
            $fs.Seek($j.Pos, 'Begin') | Out-Null
            $buf = New-Object byte[] ($fs.Length - $j.Pos)
            $n = $fs.Read($buf, 0, $buf.Length)
            $j.Pos += $n
            return [Text.Encoding]::Default.GetString($buf, 0, $n)
        } finally { $fs.Close() }
    } catch { return '' }
}

$timer.Add_Tick({
    $j = $script:job
    if (-not $j) { $timer.Stop(); return }
    $text = Read-New $j
    if ($text) {
        $j.Partial += $text
        $parts = $j.Partial -split "`r?`n"
        $j.Partial = $parts[-1]
        for ($k = 0; $k -lt $parts.Count - 1; $k++) { $l = $parts[$k]; $j.All += "$l`n"; if (-not $j.Quiet) { Add-Out $l } }
    }
    if ($j.P.HasExited) {
        $text = Read-New $j
        $rest = $j.Partial + $text
        foreach ($l in ($rest -split "`r?`n")) { $j.All += "$l`n"; if (-not $j.Quiet) { Add-Out $l } }
        if (Test-Path $j.Err) {
            $err = [IO.File]::ReadAllText($j.Err)
            if ($err.Trim() -and -not $j.Quiet) { $err -split "`r?`n" | Select-Object -First 3 | ForEach-Object { Add-Out "[!] $_" } }
        }
        Remove-Item $j.Out, $j.Err -ErrorAction SilentlyContinue
        $timer.Stop()
        $script:job = $null
        & $j.Done $j.P.ExitCode $j.All
    }
})

function Invoke-Emy([string]$argLine, [scriptblock]$done, [switch]$Quiet, [string]$title) {
    if ($script:job) { return }
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    $p = Start-Process powershell.exe -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err `
           -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Main`" $argLine"
    $null = $p.Handle   # ExitCode okunabilsin diye
    if (-not $Quiet) {
        Set-Busy $true $title
        Add-Out "> $title"
    }
    $script:job = @{ P = $p; Out = $out; Err = $err; Pos = 0; Partial = ''; All = ''; Quiet = [bool]$Quiet; Done = $done }
    $timer.Start()
}

$ActionButtons = @('InstallBtn', 'StartBtn', 'StopBtn', 'UninstallBtn', 'CbDiscord', 'CbRoblox', 'ModePanel')
function Set-Busy([bool]$busy, [string]$title) {
    foreach ($b in $ActionButtons) { $ui[$b].IsEnabled = -not $busy }
    $ui.BusyText.Text = $(if ($busy) { "$title..." } else { '' })
    $win.Cursor = $(if ($busy) { [Windows.Input.Cursors]::AppStarting } else { $null })
}

# ---------------- durum ----------------
$script:status = $null
$script:firstStatus = $true
$ModeNames = @{ auto = 'Otomatik'; tlsrec = 'tlsrec'; multi = 'multi'; recfrag = 'recfrag'; frag = 'frag' }

function Show-Status($s) {
    $script:status = $s
    $installed = $s.hosts -and $s.task
    if ($installed -and $s.proxy) {
        $ui.StateDot.Fill = Brush '#3BA55D'; $ui.StateText.Text = 'Çalışıyor'
        $ui.StateSub.Text = 'Seçili servisler açık. Bilgisayar her açıldığında kendiliğinden çalışır, bu pencereyi kapatabilirsin.'
    } elseif ($installed) {
        $ui.StateDot.Fill = Brush '#FAA61A'; $ui.StateText.Text = 'Kurulu ama proxy kapalı'
        $ui.StateSub.Text = 'Proxy kapalıyken seçili servislere bağlanılamaz. "Başlat"a bas.'
    } elseif ($s.hosts -or $s.task) {
        $ui.StateDot.Fill = Brush '#FAA61A'; $ui.StateText.Text = 'Kurulum eksik'
        $ui.StateSub.Text = '"Kur / Onar" ile tamamla.'
    } else {
        $ui.StateDot.Fill = Brush '#9AA0C8'; $ui.StateText.Text = 'Kurulu değil'
        $ui.StateSub.Text = 'Servisleri seç ve "Kur / Onar"a bas. Bir kez kurman yeterli.'
    }
    $svc = @($s.services)
    $ui.SvcVal.Text   = $(if ($svc.Count) { $svc -join ' + ' } else { '-' })
    $ui.ProxyVal.Text = $(if ($s.proxy) { '● Açık' } else { '○ Kapalı' })
    $ui.ProxyVal.Foreground = Brush $(if ($s.proxy) { '#7FD99A' } else { '#9AA0C8' })
    $ui.TaskVal.Text  = $(if ($s.task) { '● Açık' } else { '○ Kapalı' })
    $ui.TaskVal.Foreground = Brush $(if ($s.task) { '#7FD99A' } else { '#9AA0C8' })
    $m = [string]$s.mode
    if (-not $m) { $ui.ModeVal.Text = '-' }
    elseif ($m -eq 'auto') { $ui.ModeVal.Text = 'Otomatik' + $(if ($s.learned) { " ($($s.learned))" } else { '' }) }
    else { $ui.ModeVal.Text = "$m (elle)" }

    $c = @($s.conflicts)
    if ($c.Count) {
        $ui.ConflictText.Text = "Çakışan program çalışıyor: $($c -join ', '). EMYDPI ile aynı anda çalışamaz; kaldırman gerekir. 'Kur / Onar' istersen durdurur."
        $ui.ConflictBox.Visibility = 'Visible'
    } else { $ui.ConflictBox.Visibility = 'Collapsed' }

    if ($script:firstStatus) {
        # ilk acilista mevcut kurulumu yansit
        $script:firstStatus = $false
        if ($svc.Count) { $ui.CbDiscord.IsChecked = $svc -contains 'Discord'; $ui.CbRoblox.IsChecked = $svc -contains 'Roblox' }
        if ($m) { foreach ($rb in $ui.ModePanel.Children) { $rb.IsChecked = ($rb.Tag -eq $m) } }
    }
}

function Refresh-Status {
    Invoke-Emy '-Action statusjson' -Quiet -done {
        param($code, $all)
        try {
            $json = ($all -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
            Show-Status ($json | ConvertFrom-Json)
        } catch { $ui.StateText.Text = 'Durum okunamadı'; Add-Out "[!] Durum okunamadı: $all" }
    }
}

$AfterAction = {
    param($code, $all)
    Set-Busy $false ''
    switch ($code) {
        0 { }
        2 { [Windows.MessageBox]::Show($win,
              "Antivirüs programın Windows'un hosts dosyasını koruyor ve yazmayı engelledi.`n`nAntivirüsü (ör. Kaspersky) birkaç dakikalığına duraklat, tekrar dene, sonra korumayı geri aç. Bu sadece kurulum ve kaldırmada gerekir.",
              'EMYDPI - hosts engellendi', 'OK', 'Warning') | Out-Null }
        3 { [Windows.MessageBox]::Show($win, ($all.Trim()), 'EMYDPI - desteklenmiyor', 'OK', 'Error') | Out-Null }
        4 { [Windows.MessageBox]::Show($win, "443 portunu başka bir program kullanıyor (XAMPP/Apache, IIS, VMware vb.).`nO programı kapatıp tekrar dene.", 'EMYDPI - port dolu', 'OK', 'Warning') | Out-Null }
        default { Add-Out "[!] İşlem hata koduyla bitti ($code). Ayrıntı için 'Logu göster'." }
    }
    Refresh-Status
}

# ---------------- butonlar ----------------
$ui.InstallBtn.Add_Click({
    $svc = @()
    if ($ui.CbDiscord.IsChecked) { $svc += 'Discord' }
    if ($ui.CbRoblox.IsChecked)  { $svc += 'Roblox' }
    if ($svc.Count -eq 0) { [Windows.MessageBox]::Show($win, 'En az bir servis seç (Discord veya Roblox).', 'EMYDPI') | Out-Null; return }
    $mode = ($ui.ModePanel.Children | Where-Object { $_.IsChecked } | Select-Object -First 1).Tag
    if (-not $mode) { $mode = 'auto' }
    $flag = '-NoPrompt'
    $c = @(); if ($script:status) { $c = @($script:status.conflicts) }
    if ($c.Count) {
        $r = [Windows.MessageBox]::Show($win,
            "EMYDPI ile çakışan programlar çalışıyor:`n`n  $($c -join "`n  ")`n`nBunlar EMYDPI ile aynı anda çalışamaz. Şimdi durdurup otomatik başlamalarını kapatayım mı?`n`n(Kalıcı çözüm onları tamamen kaldırmaktır.)",
            'EMYDPI - çakışan program', 'YesNoCancel', 'Warning')
        if ($r -eq 'Cancel') { return }
        if ($r -eq 'Yes') { $flag = '-StopConflicts' }
    }
    Invoke-Emy "-Action install -Services `"$($svc -join ',')`" -Mode $mode $flag" -title 'Kuruluyor' -done $AfterAction
})
$ui.StartBtn.Add_Click({ Invoke-Emy '-Action start' -title 'Başlatılıyor' -done $AfterAction })
$ui.StopBtn.Add_Click({ Invoke-Emy '-Action stop' -title 'Durduruluyor' -done $AfterAction })
$ui.UninstallBtn.Add_Click({
    $r = [Windows.MessageBox]::Show($win, "EMYDPI tamamen kaldırılsın mı?`n`nProxy, otomatik başlatma ve hosts kayıtları silinir. Discord/Roblox eski haline döner (yani tekrar engellenir).",
                                    'EMYDPI - kaldır', 'YesNo', 'Question')
    if ($r -eq 'Yes') { Invoke-Emy '-Action uninstall' -title 'Kaldırılıyor' -done $AfterAction }
})
$ui.LogBtn.Add_Click({
    Add-Out '> Son log kayıtları'
    if (Test-Path $LogFile) { Get-Content $LogFile -Tail 25 | ForEach-Object { Add-Out $_ } } else { Add-Out 'Log yok.' }
})
$ui.FolderBtn.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$Dir`"" })
$ui.RepoLink.Add_MouseLeftButtonUp({ Start-Process explorer.exe -ArgumentList $Repo })
$ui.AdvToggle.Add_Checked({ $ui.AdvPanel.Visibility = 'Visible' })
$ui.AdvToggle.Add_Unchecked({ $ui.AdvPanel.Visibility = 'Collapsed' })
$ui.CloseBtn.Add_Click({ $win.Close() })
$ui.MinBtn.Add_Click({ $win.WindowState = 'Minimized' })
$ui.TitleBar.Add_MouseLeftButtonDown({ $win.DragMove() })

$win.Add_ContentRendered({ Refresh-Status })

# Gelistirici: EMYDPI_SNAPSHOT=dosya.png ise pencereyi resme cizip kapanir (README gorseli icin)
if ($env:EMYDPI_SNAPSHOT) {
    $snap = New-Object Windows.Threading.DispatcherTimer
    $snap.Interval = [TimeSpan]::FromSeconds([double]$(if ($env:EMYDPI_SNAPSHOT_WAIT) { $env:EMYDPI_SNAPSHOT_WAIT } else { 4 }))
    $snap.Add_Tick({
        $snap.Stop()
        if ($env:EMYDPI_SNAPSHOT_ADV) { $ui.AdvToggle.IsChecked = $true; $win.UpdateLayout() }
        $el = $win.Content
        $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int](($el.ActualWidth + 30) * 2)), ([int](($el.ActualHeight + 30) * 2)), 192, 192, ([Windows.Media.PixelFormats]::Pbgra32)
        $rtb.Render($el)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [IO.File]::Create($env:EMYDPI_SNAPSHOT); $enc.Save($fs); $fs.Close()
        $win.Close()
    })
    $snap.Start()
}
$null = $win.ShowDialog()
