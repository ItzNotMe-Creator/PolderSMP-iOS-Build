using System;
using System.IO;
using System.Drawing;
using System.Windows.Forms;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;
using System.Threading.Tasks;

internal static class Program
{
    [STAThread] static void Main(){
        ApplicationConfiguration.Initialize();
        Application.Run(new ControlWindow());
    }
}
internal sealed class ControlWindow : Form
{
    private readonly string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PolderSMP","Client");
    private readonly WebView2 web = new(){Dock=DockStyle.Fill};
    private readonly Label status = new(){AutoSize=true,ForeColor=Color.FromArgb(160,172,189),Margin=new Padding(8,10,8,0)};
    private readonly Panel content = new(){Dock=DockStyle.Fill};
    private readonly Panel welcome = new(){Dock=DockStyle.Fill,BackColor=Color.FromArgb(15,18,24)};
    private readonly TextBox address = new(){Width=410,Font=new Font("Segoe UI",11)};
    private Uri? origin;
    private bool ready, connecting;
    public ControlWindow(){
        Text="PolderSMP Control";MinimumSize=new Size(650,520);Size=new Size(1100,760);
        StartPosition=FormStartPosition.CenterScreen;BackColor=Color.FromArgb(15,18,24);ForeColor=Color.White;
        Font=new Font("Segoe UI",10);Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        var bar=new FlowLayoutPanel{Dock=DockStyle.Top,Height=48,BackColor=Color.FromArgb(24,30,40),Padding=new Padding(10,4,0,0),WrapContents=false};
        var brand=new Label{Text="PolderSMP  /  Control",AutoSize=true,Font=new Font("Segoe UI",12,FontStyle.Bold),Margin=new Padding(3,8,18,0)};
        bar.Controls.Add(brand);
        bar.Controls.Add(Button("Vernieuwen",()=>{if(ready&&origin!=null)web.Reload();}));
        bar.Controls.Add(Button("Verbinding",()=>{if(connecting)return;if(origin!=null){web.Visible=false;web.CoreWebView2.Navigate("about:blank");}welcome.Visible=true;welcome.BringToFront();status.Text="Serveradres instellen";}));
        bar.Controls.Add(status);
        Controls.Add(content);Controls.Add(bar);
        content.Controls.Add(web);content.Controls.Add(welcome);web.Visible=false;
        var stack=new TableLayoutPanel{AutoSize=true,ColumnCount=1,RowCount=7,Anchor=AnchorStyles.None,Padding=new Padding(12),BackColor=welcome.BackColor};
        var logo=new PictureBox{Width=64,Height=64,SizeMode=PictureBoxSizeMode.Zoom,Image=Icon.ToBitmap(),Margin=new Padding(0,0,0,16)};
        stack.Controls.Add(logo);
        stack.Controls.Add(new Label{Text="Welkom bij PolderSMP",AutoSize=true,Font=new Font("Segoe UI",24,FontStyle.Bold),Margin=new Padding(0,0,0,8)});
        stack.Controls.Add(new Label{Text="Verbind met je eigen serveraccount. Je toegang wordt bepaald door de eigenaar.",AutoSize=true,MaximumSize=new Size(430,0),ForeColor=Color.FromArgb(170,181,198),Margin=new Padding(0,0,0,24)});
        stack.Controls.Add(new Label{Text="Privé HTTPS-serveradres (Tailscale)",AutoSize=true,Margin=new Padding(0,0,0,6)});
        address.PlaceholderText="https://voorbeeld.ts.net:8443/";
        stack.Controls.Add(address);
        var connect=Button("Verbinden",async()=>await Connect());connect.Width=410;connect.Height=42;connect.Margin=new Padding(0,14,0,12);stack.Controls.Add(connect);
        stack.Controls.Add(new Label{Text="Tailscale moet verbonden zijn. Log daarna in met je persoonlijke code.",AutoSize=true,MaximumSize=new Size(430,0),ForeColor=Color.FromArgb(155,168,186)});
        welcome.Controls.Add(stack);
        welcome.Resize+=(_,_)=>Center();stack.SizeChanged+=(_,_)=>Center();
        void Center(){stack.Location=new Point(Math.Max(0,(welcome.ClientSize.Width-stack.Width)/2),Math.Max(0,(welcome.ClientSize.Height-stack.Height)/2));}
        address.KeyDown+=async(_,e)=>{if(e.KeyCode==Keys.Enter){e.SuppressKeyPress=true;await Connect();}};
        Shown+=async(_,_)=>{try{Directory.CreateDirectory(data);var file=Path.Combine(data,"server.txt");if(File.Exists(file)){address.Text=File.ReadAllText(file);await Connect();}}catch(Exception e){status.Text="Instellingen niet beschikbaar";MessageBox.Show(this,e.Message,"PolderSMP");}};
    }
    private static Button Button(string text,Action click){
        var b=new Button{Text=text,AutoSize=true,Height=32,FlatStyle=FlatStyle.Flat,BackColor=Color.FromArgb(40,61,88),ForeColor=Color.White,Cursor=Cursors.Hand,Margin=new Padding(4,2,4,2)};
        b.FlatAppearance.BorderSize=0;b.Click+=(_,_)=>click();return b;
    }
    internal static Uri? ValidateAddress(string value){
        value=value.Trim();if(!value.Contains("://"))value="https://"+value;
        if(!Uri.TryCreate(value,UriKind.Absolute,out var u)||u.Scheme!="https"||!u.IdnHost.EndsWith(".ts.net",StringComparison.OrdinalIgnoreCase)||u.IdnHost.Length<=7||u.UserInfo.Length!=0||u.AbsolutePath!="/"||u.Query.Length!=0||u.Fragment.Length!=0)return null;
        return new Uri(u.GetLeftPart(UriPartial.Authority)+"/");
    }
    private bool Allowed(string url){
        return origin!=null&&Uri.TryCreate(url,UriKind.Absolute,out var u)&&u.Scheme=="https"&&string.Equals(u.IdnHost,origin.IdnHost,StringComparison.OrdinalIgnoreCase)&&u.Port==origin.Port;
    }
    private async Task Connect(){
        if(connecting)return;
        var target=ValidateAddress(address.Text);
        if(target==null){MessageBox.Show(this,"Gebruik een geldig HTTPS-adres van Tailscale Serve, eventueel met poort.","Ongeldig adres");return;}
        connecting=true;status.Text="Verbinden…";
        try{
            if(!ready){
                Directory.CreateDirectory(data);
                var env=await CoreWebView2Environment.CreateAsync(null,Path.Combine(data,"WebView"));
                await web.EnsureCoreWebView2Async(env);
                var core=web.CoreWebView2;
                core.Settings.AreDefaultContextMenusEnabled=false;core.Settings.AreDevToolsEnabled=false;
                core.Settings.IsPasswordAutosaveEnabled=false;core.Settings.IsGeneralAutofillEnabled=false;
                core.NavigationStarting+=(_,e)=>{if(e.Uri!="about:blank"&&!Allowed(e.Uri))e.Cancel=true;};
                core.FrameNavigationStarting+=(_,e)=>{if(e.Uri!="about:blank"&&!Allowed(e.Uri))e.Cancel=true;};
                core.NewWindowRequested+=(_,e)=>e.Handled=true;
                core.PermissionRequested+=(_,e)=>e.State=CoreWebView2PermissionState.Deny;
                core.DownloadStarting+=(_,e)=>e.Cancel=true;
                core.NavigationCompleted+=(_,e)=>{
                    if(core.Source=="about:blank")return;
                    if(!e.IsSuccess){status.Text="Niet verbonden";web.Visible=false;welcome.Visible=true;welcome.BringToFront();return;}
                    status.Text="Verbonden";welcome.Visible=false;web.Visible=true;web.BringToFront();
                    if(origin!=null)File.WriteAllText(Path.Combine(data,"server.txt"),origin.AbsoluteUri);
                };
                ready=true;
            }
            origin=target;web.CoreWebView2.Navigate(target.AbsoluteUri);
        }catch(WebView2RuntimeNotFoundException){status.Text="WebView2 ontbreekt";MessageBox.Show(this,"Installeer Microsoft Edge WebView2 Runtime via Microsoft en open PolderSMP opnieuw.","WebView2 vereist");}
        catch(Exception e){status.Text="Verbinding mislukt";MessageBox.Show(this,e.Message,"PolderSMP");}
        finally{connecting=false;}
    }
}
