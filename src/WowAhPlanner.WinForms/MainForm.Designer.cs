namespace WowAhPlanner.WinForms;

partial class MainForm
{
    private System.ComponentModel.IContainer components = null;

    private SplitContainer rootSplit;

    private Panel sidebarPanel;
    private Label brandLabel;
    private FlowLayoutPanel navFlowPanel;
    private Ui.NavButton navHomeButton;
    private Ui.NavButton navRecipesButton;
    private Ui.NavButton navPlanButton;
    private Ui.NavButton navPricesButton;
    private Ui.NavButton navTargetsButton;
    private Ui.NavButton navUploadButton;
    private Ui.NavButton navOwnedButton;

    private Panel mainPanel;
    private TableLayoutPanel mainLayout;

    private Panel headerPanel;
    private TableLayoutPanel headerLayout;
    private Button headerMenuButton;
    private Label headerTitleLabel;
    private Button headerActionButton;
    private Panel headerDivider;

    private Panel contentOuterPanel;
    private Panel pageHostPanel;

    private ContextMenuStrip navMenuStrip;
    private ToolStripMenuItem navHomeMenuItem;
    private ToolStripMenuItem navRecipesMenuItem;
    private ToolStripMenuItem navPlanMenuItem;
    private ToolStripMenuItem navPricesMenuItem;
    private ToolStripMenuItem navTargetsMenuItem;
    private ToolStripMenuItem navUploadMenuItem;
    private ToolStripMenuItem navOwnedMenuItem;

    protected override void Dispose(bool disposing)
    {
        if (disposing && (components != null))
        {
            components.Dispose();
        }
        base.Dispose(disposing);
    }

    private void InitializeComponent()
    {
        components = new System.ComponentModel.Container();

        rootSplit = new SplitContainer();

        sidebarPanel = new Panel();
        brandLabel = new Label();
        navFlowPanel = new FlowLayoutPanel();
        navHomeButton = new Ui.NavButton();
        navRecipesButton = new Ui.NavButton();
        navPlanButton = new Ui.NavButton();
        navPricesButton = new Ui.NavButton();
        navTargetsButton = new Ui.NavButton();
        navUploadButton = new Ui.NavButton();
        navOwnedButton = new Ui.NavButton();

        mainPanel = new Panel();
        mainLayout = new TableLayoutPanel();

        headerPanel = new Panel();
        headerLayout = new TableLayoutPanel();
        headerMenuButton = new Button();
        headerTitleLabel = new Label();
        headerActionButton = new Button();
        headerDivider = new Panel();

        contentOuterPanel = new Panel();
        pageHostPanel = new Panel();

        navMenuStrip = new ContextMenuStrip(components);
        navHomeMenuItem = new ToolStripMenuItem();
        navRecipesMenuItem = new ToolStripMenuItem();
        navPlanMenuItem = new ToolStripMenuItem();
        navPricesMenuItem = new ToolStripMenuItem();
        navTargetsMenuItem = new ToolStripMenuItem();
        navUploadMenuItem = new ToolStripMenuItem();
        navOwnedMenuItem = new ToolStripMenuItem();

        ((System.ComponentModel.ISupportInitialize)rootSplit).BeginInit();
        rootSplit.Panel1.SuspendLayout();
        rootSplit.Panel2.SuspendLayout();
        rootSplit.SuspendLayout();
        SuspendLayout();

        // MainForm
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(1200, 760);
        MinimumSize = new Size(760, 560);
        StartPosition = FormStartPosition.CenterScreen;
        Text = "Profession Leveler";
        Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);

        // navMenuStrip
        navHomeMenuItem.Text = "Home";
        navRecipesMenuItem.Text = "Recipes";
        navPlanMenuItem.Text = "Plan";
        navPricesMenuItem.Text = "Prices";
        navTargetsMenuItem.Text = "Targets";
        navUploadMenuItem.Text = "Upload";
        navOwnedMenuItem.Text = "Owned";
        navMenuStrip.Items.AddRange(new ToolStripItem[]
        {
            navHomeMenuItem,
            navRecipesMenuItem,
            navPlanMenuItem,
            navPricesMenuItem,
            navTargetsMenuItem,
            navUploadMenuItem,
            navOwnedMenuItem,
        });

        // rootSplit
        rootSplit.Dock = DockStyle.Fill;
        rootSplit.Margin = new Padding(0);
        rootSplit.Padding = new Padding(0);
        rootSplit.SplitterWidth = 1;
        rootSplit.FixedPanel = FixedPanel.Panel1;
        rootSplit.IsSplitterFixed = true;
        rootSplit.Panel1MinSize = 0;
        rootSplit.Panel2MinSize = 0;

        // sidebarPanel
        sidebarPanel.Dock = DockStyle.Fill;
        sidebarPanel.Margin = new Padding(0);
        sidebarPanel.Padding = new Padding(16);

        // brandLabel
        brandLabel.AutoSize = true;
        brandLabel.Dock = DockStyle.Top;
        brandLabel.Margin = new Padding(0, 0, 0, 12);
        brandLabel.Text = "Profession Leveler";

        // navFlowPanel
        navFlowPanel.Dock = DockStyle.Top;
        navFlowPanel.FlowDirection = FlowDirection.TopDown;
        navFlowPanel.WrapContents = false;
        navFlowPanel.AutoSize = true;
        navFlowPanel.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        navFlowPanel.Margin = new Padding(0);
        navFlowPanel.Padding = new Padding(0);

        navHomeButton.Text = "Home";
        navHomeButton.Margin = new Padding(0, 0, 0, 8);

        navRecipesButton.Text = "Recipes";
        navRecipesButton.Margin = new Padding(0, 0, 0, 8);

        navPlanButton.Text = "Plan";
        navPlanButton.Margin = new Padding(0, 0, 0, 8);

        navPricesButton.Text = "Prices";
        navPricesButton.Margin = new Padding(0, 0, 0, 8);

        navTargetsButton.Text = "Targets";
        navTargetsButton.Margin = new Padding(0, 0, 0, 8);

        navUploadButton.Text = "Upload";
        navUploadButton.Margin = new Padding(0, 0, 0, 8);

        navOwnedButton.Text = "Owned";
        navOwnedButton.Margin = new Padding(0);

        navFlowPanel.Controls.Add(navHomeButton);
        navFlowPanel.Controls.Add(navRecipesButton);
        navFlowPanel.Controls.Add(navPlanButton);
        navFlowPanel.Controls.Add(navPricesButton);
        navFlowPanel.Controls.Add(navTargetsButton);
        navFlowPanel.Controls.Add(navUploadButton);
        navFlowPanel.Controls.Add(navOwnedButton);

        sidebarPanel.Controls.Add(navFlowPanel);
        sidebarPanel.Controls.Add(brandLabel);
        rootSplit.Panel1.Controls.Add(sidebarPanel);

        // mainPanel
        mainPanel.Dock = DockStyle.Fill;
        mainPanel.Margin = new Padding(0);
        mainPanel.Padding = new Padding(24);
        rootSplit.Panel2.Controls.Add(mainPanel);

        // mainLayout
        mainLayout.ColumnCount = 1;
        mainLayout.RowCount = 2;
        mainLayout.Dock = DockStyle.Fill;
        mainLayout.Margin = new Padding(0);
        mainLayout.Padding = new Padding(0);
        mainLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 56F));
        mainLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        mainPanel.Controls.Add(mainLayout);

        // headerPanel
        headerPanel.Dock = DockStyle.Fill;
        headerPanel.Margin = new Padding(0, 0, 0, 16);
        headerPanel.Padding = new Padding(0);

        // headerDivider
        headerDivider.Dock = DockStyle.Bottom;
        headerDivider.Height = 1;
        headerDivider.Margin = new Padding(0);

        // headerLayout
        headerLayout.ColumnCount = 3;
        headerLayout.RowCount = 1;
        headerLayout.Dock = DockStyle.Fill;
        headerLayout.Margin = new Padding(0);
        headerLayout.Padding = new Padding(0);
        headerLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 40F));
        headerLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        headerLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120F));
        headerLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

        // headerMenuButton
        headerMenuButton.Text = "\u2630";
        headerMenuButton.Margin = new Padding(0);
        headerMenuButton.Size = new Size(36, 32);
        headerMenuButton.Anchor = AnchorStyles.Left;

        // headerTitleLabel
        headerTitleLabel.Text = "Home";
        headerTitleLabel.Dock = DockStyle.Fill;
        headerTitleLabel.Margin = new Padding(0);
        headerTitleLabel.TextAlign = ContentAlignment.MiddleLeft;

        // headerActionButton
        headerActionButton.Text = "Refresh";
        headerActionButton.Margin = new Padding(0);
        headerActionButton.Size = new Size(120, 32);
        headerActionButton.Anchor = AnchorStyles.Right;

        headerLayout.Controls.Add(headerMenuButton, 0, 0);
        headerLayout.Controls.Add(headerTitleLabel, 1, 0);
        headerLayout.Controls.Add(headerActionButton, 2, 0);

        headerPanel.Controls.Add(headerLayout);
        headerPanel.Controls.Add(headerDivider);

        // contentOuterPanel
        contentOuterPanel.Dock = DockStyle.Fill;
        contentOuterPanel.Margin = new Padding(0);
        contentOuterPanel.Padding = new Padding(0);
        contentOuterPanel.AutoScroll = false;

        // pageHostPanel
        pageHostPanel.Dock = DockStyle.Fill;
        pageHostPanel.AutoScroll = false;
        pageHostPanel.Margin = new Padding(0);
        pageHostPanel.Padding = new Padding(0);

        contentOuterPanel.Controls.Add(pageHostPanel);

        mainLayout.Controls.Add(headerPanel, 0, 0);
        mainLayout.Controls.Add(contentOuterPanel, 0, 1);

        Controls.Add(rootSplit);

        rootSplit.Panel1.ResumeLayout(false);
        rootSplit.Panel1.PerformLayout();
        rootSplit.Panel2.ResumeLayout(false);
        ((System.ComponentModel.ISupportInitialize)rootSplit).EndInit();
        rootSplit.ResumeLayout(false);
        ResumeLayout(false);
    }
}
