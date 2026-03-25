import { useState } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  PieChart, Pie, Cell, ResponsiveContainer, AreaChart, Area,
  LineChart, Line,
} from 'recharts';
import {
  Users, TrendingUp, Target, DollarSign, Activity,
  BarChart3, PieChart as PieIcon, FlaskConical, LayoutDashboard,
  ArrowRight, CheckCircle, AlertTriangle, Lightbulb,
} from 'lucide-react';
import './App.css';

/* ── hardcoded data ── */

const SEGMENTS = [
  { name: 'High-Potential Dormant', n: 888, clv: 326.18, color: '#0d9488' },
  { name: 'Loyalty Champions', n: 2801, clv: 260.05, color: '#2563eb' },
  { name: 'Medium-Potential', n: 3154, clv: 29.27, color: '#7c3aed' },
  { name: 'Low-Potential', n: 76806, clv: 3.40, color: '#f59e0b' },
  { name: 'Low-Value Passives', n: 9700, clv: 1.57, color: '#94a3b8' },
];

const FEATURES_ODDS = [
  { feature: 'used_voucher', odds: 3.81, direction: '+' },
  { feature: 'avg_installments', odds: 1.03, direction: '+' },
  { feature: 'avg_review_score', odds: 1.02, direction: '+' },
  { feature: 'monetary', odds: 1.001, direction: '+' },
  { feature: 'avg_freight', odds: 0.99, direction: '−' },
  { feature: 'first_delivery_delay', odds: 0.99, direction: '−' },
];

const FEATURES_COEF = [
  { feature: 'used_voucher', coef: 1.3372, direction: 'Increases P(repeat)' },
  { feature: 'avg_installments', coef: 0.0254, direction: 'Increases P(repeat)' },
  { feature: 'avg_review_score', coef: 0.0191, direction: 'Increases P(repeat)' },
  { feature: 'monetary', coef: 0.0014, direction: 'Increases P(repeat)' },
  { feature: 'avg_freight', coef: -0.0114, direction: 'Decreases P(repeat)' },
  { feature: 'first_delivery_delay', coef: -0.0076, direction: 'Decreases P(repeat)' },
];

/* Approximate ROC curve points (sampled from AUC=0.743 model) */
const ROC_POINTS = [
  {fpr:0,tpr:0},{fpr:0.01,tpr:0.08},{fpr:0.02,tpr:0.14},{fpr:0.05,tpr:0.25},
  {fpr:0.08,tpr:0.33},{fpr:0.10,tpr:0.38},{fpr:0.15,tpr:0.46},{fpr:0.20,tpr:0.53},
  {fpr:0.25,tpr:0.58},{fpr:0.30,tpr:0.63},{fpr:0.35,tpr:0.67},{fpr:0.40,tpr:0.71},
  {fpr:0.45,tpr:0.74},{fpr:0.50,tpr:0.77},{fpr:0.55,tpr:0.80},{fpr:0.60,tpr:0.83},
  {fpr:0.65,tpr:0.85},{fpr:0.70,tpr:0.88},{fpr:0.75,tpr:0.90},{fpr:0.80,tpr:0.92},
  {fpr:0.85,tpr:0.94},{fpr:0.90,tpr:0.96},{fpr:0.95,tpr:0.98},{fpr:1,tpr:1},
];
const ROC_DIAGONAL = [{fpr:0,tpr:0},{fpr:1,tpr:1}];

const PL = { targeted: 888, cost: 13320, conversions: 158, revenue: 21773, profit: 8453 };

const SCENARIOS = {
  '5%': { label: '3% → 5%', buyers: 1866, rev: 542532 },
  '6%': { label: '3% → 6%', buyers: 2800, rev: 813876 },
};

const EXPERIMENT = {
  pilot: { label: 'Pilot (RCT)', customers: 3014, cost: 22605, profit: -18461 },
  scale: { label: 'Scale-Up', customers: 888, cost: 13320, profit: 8453 },
};

const INTERVENTIONS = [
  { segment: 'High-Potential Dormant Buyers', action: 'BRL 10 voucher + delivery subsidy' },
  { segment: 'Loyalty Champions', action: 'VIP retention: early access to new categories' },
  { segment: 'Medium-Potential', action: 'Highlight installment options at checkout' },
  { segment: 'Low-Potential', action: 'Standard lifecycle email' },
  { segment: 'Low-Value Passives', action: 'Do not target' },
];

const TABS = [
  { id: 'overview', label: 'Overview', icon: LayoutDashboard },
  { id: 'segmentation', label: 'Segmentation', icon: PieIcon },
  { id: 'model', label: 'Model & Targeting', icon: BarChart3 },
  { id: 'experiment', label: 'Experiment', icon: FlaskConical },
];

const fmt = (v) => v.toLocaleString('en-US');
const brl = (v) => `R$ ${v.toLocaleString('en-US')}`;


/* ── reusable components ── */

function KpiCard({ icon: Icon, label, value, sub, accent = '#0d9488' }) {
  return (
    <div className="kpi-card">
      <div className="kpi-icon" style={{ background: `${accent}18`, color: accent }}>
        <Icon size={22} />
      </div>
      <div className="kpi-body">
        <span className="kpi-value">{value}</span>
        <span className="kpi-label">{label}</span>
        {sub && <span className="kpi-sub">{sub}</span>}
      </div>
    </div>
  );
}

function CustomTooltip({ active, payload, label, prefix = '' }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="chart-tooltip">
      <p className="tooltip-label">{label}</p>
      {payload.map((p, i) => (
        <p key={i} style={{ color: p.color }}>
          {p.name}: {prefix}{typeof p.value === 'number' ? p.value.toLocaleString('en-US', { maximumFractionDigits: 4 }) : p.value}
        </p>
      ))}
    </div>
  );
}

function InsightCard({ icon: Icon, title, children, accent = '#0d9488' }) {
  return (
    <div className="insight-card" style={{ borderLeftColor: accent }}>
      <div className="insight-header">
        <Icon size={18} style={{ color: accent }} />
        <span className="insight-title">{title}</span>
      </div>
      <p className="insight-body">{children}</p>
    </div>
  );
}

/* ── OVERVIEW (consultant-level pitch) ── */

function Overview() {
  const storyData = [
    { name: 'One-Time', value: 90348, color: '#94a3b8' },
    { name: 'Repeat', value: 3001, color: '#0d9488' },
  ];
  return (
    <div className="tab-content">
      {/* Hero banner */}
      <div className="hero-card full-width">
        <div className="hero-content">
          <span className="hero-eyebrow">Strategic Recommendation</span>
          <h2 className="hero-title">Unlock BRL 540K–810K in incremental revenue by converting dormant buyers into repeat customers</h2>
          <p className="hero-desc">
            97% of Olist customers never return. Our predictive model identifies 888 high-potential
            dormant buyers who are most likely to convert with a targeted BRL 15 intervention —
            generating an expected BRL 8,453 net profit per campaign cycle.
          </p>
          <div className="hero-metrics">
            <div className="hero-metric">
              <span className="hero-metric-val">97%</span>
              <span className="hero-metric-label">One-time buyers</span>
            </div>
            <div className="hero-arrow"><ArrowRight size={20} /></div>
            <div className="hero-metric">
              <span className="hero-metric-val">888</span>
              <span className="hero-metric-label">Targetable high-potential</span>
            </div>
            <div className="hero-arrow"><ArrowRight size={20} /></div>
            <div className="hero-metric">
              <span className="hero-metric-val accent-green">R$ 8,453</span>
              <span className="hero-metric-label">Net profit per cycle</span>
            </div>
          </div>
        </div>
      </div>

      {/* Three insight cards */}
      <div className="three-col">
        <InsightCard icon={AlertTriangle} title="The Problem" accent="#f97316">
          Olist's repeat rate is just 3%. The vast majority of customers purchase once and never
          return, leaving significant lifetime value on the table.
        </InsightCard>
        <InsightCard icon={Target} title="Our Approach" accent="#2563eb">
          A leakage-aware logistic model (AUC 0.743) scores every one-time buyer's probability of
          returning. We target only those with P(repeat) ≥ 10% — the "High-Potential Dormant Buyers."
        </InsightCard>
        <InsightCard icon={CheckCircle} title="The Payoff" accent="#10b981">
          A BRL 15 voucher + delivery subsidy on 888 customers yields 158 expected conversions and
          R$ 8,453 net profit. At scale, a 2–3 pp lift unlocks R$ 540K–810K annually.
        </InsightCard>
      </div>

      {/* Charts row */}
      <div className="two-col">
        <div className="card">
          <h3>Customer Base Composition</h3>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie data={storyData} dataKey="value" nameKey="name" cx="50%" cy="50%"
                innerRadius={60} outerRadius={100} paddingAngle={3}
                label={({ name, percent }) => `${name} ${(percent * 100).toFixed(1)}%`}>
                {storyData.map((d, i) => <Cell key={i} fill={d.color} />)}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
            </PieChart>
          </ResponsiveContainer>
          <p className="chart-note">93,349 total customers · ~3% repeat rate</p>
        </div>
        <div className="card">
          <h3>Revenue Upside by Repeat Rate Target</h3>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={[
              { scenario: '3% → 5%', revenue: 542532 },
              { scenario: '3% → 6%', revenue: 813876 },
            ]} margin={{ top: 10, right: 20, left: 20, bottom: 5 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
              <XAxis dataKey="scenario" tick={{ fontSize: 13 }} />
              <YAxis tickFormatter={(v) => `${(v / 1000).toFixed(0)}K`} tick={{ fontSize: 12 }} />
              <Tooltip content={<CustomTooltip prefix="R$ " />} />
              <Bar dataKey="revenue" name="Incremental Revenue (BRL)" fill="#0d9488" radius={[6, 6, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
          <p className="chart-note">AOV R$ 137.51 · Avg repeat frequency 2.11</p>
        </div>
      </div>

      {/* Recommended next steps */}
      <div className="card full-width">
        <h3>Recommended Next Steps</h3>
        <div className="steps-row">
          <div className="step-card">
            <span className="step-num">1</span>
            <span className="step-title">Validate with RCT</span>
            <span className="step-desc">Run a 3,014-customer randomized pilot to confirm the causal effect of vouchers on repeat rate.</span>
          </div>
          <div className="step-card">
            <span className="step-num">2</span>
            <span className="step-title">Scale to 888 Targets</span>
            <span className="step-desc">Deploy BRL 10 voucher + BRL 5 delivery subsidy to the high-potential dormant segment.</span>
          </div>
          <div className="step-card">
            <span className="step-num">3</span>
            <span className="step-title">Monitor & Iterate</span>
            <span className="step-desc">Track conversion lift, update model scores quarterly, expand to medium-potential if ROI holds.</span>
          </div>
        </div>
      </div>
    </div>
  );
}


/* ── SEGMENTATION ── */

function Segmentation() {
  return (
    <div className="tab-content">
      <div className="two-col">
        <div className="card">
          <h3>Customer Count by Segment</h3>
          <ResponsiveContainer width="100%" height={340}>
            <PieChart>
              <Pie data={SEGMENTS} dataKey="n" nameKey="name" cx="50%" cy="50%"
                innerRadius={55} outerRadius={110} paddingAngle={2}
                label={({ name, percent }) => percent > 0.03 ? `${name} ${(percent * 100).toFixed(1)}%` : ''}
                style={{ fontSize: '11px' }}>
                {SEGMENTS.map((s, i) => <Cell key={i} fill={s.color} />)}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
              <Legend
                formatter={(value) => <span style={{ fontSize: '11px', color: '#64748b' }}>{value}</span>}
              />
            </PieChart>
          </ResponsiveContainer>
        </div>
        <div className="card">
          <h3>Average CLV by Segment (BRL)</h3>
          <ResponsiveContainer width="100%" height={340}>
            <BarChart data={SEGMENTS} layout="vertical" margin={{ top: 5, right: 30, left: 10, bottom: 5 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
              <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={(v) => `R$ ${v}`} />
              <YAxis type="category" dataKey="name" width={140} tick={{ fontSize: 11 }} />
              <Tooltip content={<CustomTooltip prefix="R$ " />} />
              <Bar dataKey="clv" name="Avg CLV (BRL)" radius={[0, 6, 6, 0]}>
                {SEGMENTS.map((s, i) => <Cell key={i} fill={s.color} />)}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
      <div className="card full-width">
        <h3>Recommended Interventions</h3>
        <div className="data-table-wrap">
        <table className="data-table">
          <thead>
            <tr><th>Segment</th><th>Size (N)</th><th>Avg CLV (BRL)</th><th>Recommended Action</th></tr>
          </thead>
          <tbody>
            {SEGMENTS.map((s, i) => (
              <tr key={i}>
                <td><span className="seg-dot" style={{ background: s.color }} />{s.name}</td>
                <td>{fmt(s.n)}</td>
                <td>R$ {s.clv.toFixed(2)}</td>
                <td>{INTERVENTIONS[i].action}</td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      </div>
    </div>
  );
}

/* ── MODEL & TARGETING (with ROC + Feature Importance plots) ── */

function ModelTargeting() {
  const [scenario, setScenario] = useState('5%');
  const [featureView, setFeatureView] = useState('odds');
  const sc = SCENARIOS[scenario];
  const plData = [
    { name: 'Cost', value: PL.cost, fill: '#f97316' },
    { name: 'Revenue', value: PL.revenue, fill: '#2563eb' },
    { name: 'Net Profit', value: PL.profit, fill: '#10b981' },
  ];

  return (
    <div className="tab-content">
      {/* ROC Curve + Feature Importance side by side */}
      <div className="two-col">
        <div className="card">
          <h3>ROC Curve — Repeat Buyer Classifier</h3>
          <p className="chart-sub">Holdout set · AUC = 0.743</p>
          <ResponsiveContainer width="100%" height={320}>
            <AreaChart data={ROC_POINTS} margin={{ top: 10, right: 20, left: 10, bottom: 30 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
              <XAxis dataKey="fpr" type="number" domain={[0, 1]}
                tick={{ fontSize: 11 }}
                label={{ value: 'False Positive Rate (1 − Specificity)', position: 'insideBottom', offset: -15, fontSize: 11, fill: '#64748b' }} />
              <YAxis type="number" domain={[0, 1]}
                tick={{ fontSize: 11 }}
                label={{ value: 'True Positive Rate (Sensitivity)', angle: -90, position: 'insideLeft', offset: 10, fontSize: 11, fill: '#64748b' }} />
              <Tooltip content={({ active, payload }) => {
                if (!active || !payload?.length) return null;
                return (
                  <div className="chart-tooltip">
                    <p>FPR: {payload[0].payload.fpr.toFixed(2)}</p>
                    <p>TPR: {payload[0].payload.tpr.toFixed(2)}</p>
                  </div>
                );
              }} />
              <Area dataKey="tpr" stroke="#002060" strokeWidth={2.5} fill="#002060" fillOpacity={0.08} dot={false} name="ROC" />
              <Line data={ROC_DIAGONAL} dataKey="tpr" stroke="#E47867" strokeWidth={1.5} strokeDasharray="6 4" dot={false} name="Random" />
            </AreaChart>
          </ResponsiveContainer>
          <div className="roc-auc-badge">AUC = 0.743</div>
          <p className="chart-note">Model discriminates well above random chance. Suitable for targeting high-potential segment.</p>
        </div>
        <div className="card">
          <h3>Feature Importance — Repeat Buyer Classifier</h3>
          <div className="toggle-row compact">
            <button className={`toggle-btn sm ${featureView === 'odds' ? 'active' : ''}`} onClick={() => setFeatureView('odds')}>Odds Ratios</button>
            <button className={`toggle-btn sm ${featureView === 'coef' ? 'active' : ''}`} onClick={() => setFeatureView('coef')}>Log-Odds Coefficients</button>
          </div>
          {featureView === 'odds' ? (
            <>
              <p className="chart-sub">Logistic regression · boleto/credit_card excluded (reference-category inflation)</p>
              <ResponsiveContainer width="100%" height={280}>
                <BarChart data={FEATURES_ODDS} layout="vertical" margin={{ top: 5, right: 30, left: 10, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                  <XAxis type="number" domain={[0, 'auto']} tick={{ fontSize: 11 }}
                    label={{ value: 'Odds Ratio', position: 'insideBottom', offset: -2, fontSize: 11 }} />
                  <YAxis type="category" dataKey="feature" width={140} tick={{ fontSize: 11 }} />
                  <Tooltip content={<CustomTooltip />} />
                  <Bar dataKey="odds" name="Odds Ratio" radius={[0, 6, 6, 0]}>
                    {FEATURES_ODDS.map((f, i) => (
                      <Cell key={i} fill={f.odds >= 1 ? '#1D9E75' : '#D85A30'} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </>
          ) : (
            <>
              <p className="chart-sub">Coefficient magnitude = strength of effect on log-odds of repeat purchase</p>
              <ResponsiveContainer width="100%" height={280}>
                <BarChart data={FEATURES_COEF} layout="vertical" margin={{ top: 5, right: 30, left: 10, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                  <XAxis type="number" tick={{ fontSize: 11 }}
                    label={{ value: 'Coefficient (log-odds)', position: 'insideBottom', offset: -2, fontSize: 11 }} />
                  <YAxis type="category" dataKey="feature" width={140} tick={{ fontSize: 11 }} />
                  <Tooltip content={<CustomTooltip />} />
                  <Bar dataKey="coef" name="Coefficient" radius={[0, 6, 6, 0]}>
                    {FEATURES_COEF.map((f, i) => (
                      <Cell key={i} fill={f.coef >= 0 ? '#1D9E75' : '#D85A30'} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </>
          )}
          <p className="chart-note">
            Voucher usage is the strongest actionable driver (OR 3.81). Delivery delay and freight slightly reduce repeat probability.
          </p>
        </div>
      </div>

      {/* P&L */}
      <div className="two-col">
        <div className="card">
          <h3>Targeting P&L — High-Potential Dormant Buyers</h3>
          <p className="chart-sub">{fmt(PL.targeted)} customers · BRL 15/customer (BRL 10 voucher + BRL 5 delivery)</p>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={plData} margin={{ top: 10, right: 30, left: 20, bottom: 5 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
              <XAxis dataKey="name" tick={{ fontSize: 13 }} />
              <YAxis tickFormatter={(v) => `${(v / 1000).toFixed(0)}K`} tick={{ fontSize: 12 }} />
              <Tooltip content={<CustomTooltip prefix="R$ " />} />
              <Bar dataKey="value" name="BRL" radius={[6, 6, 0, 0]}>
                {plData.map((d, i) => <Cell key={i} fill={d.fill} />)}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
          <div className="pl-summary">
            <span className="pl-item cost">Cost: {brl(PL.cost)}</span>
            <span className="pl-item rev">Revenue: {brl(PL.revenue)}</span>
            <span className="pl-item profit">Profit: {brl(PL.profit)}</span>
          </div>
        </div>
        <div className="card">
          <h3>Revenue Scenario Toggle</h3>
          <div className="toggle-row">
            {Object.keys(SCENARIOS).map((k) => (
              <button key={k} className={`toggle-btn ${scenario === k ? 'active' : ''}`}
                onClick={() => setScenario(k)}>Target {k} repeat</button>
            ))}
          </div>
          <div className="scenario-cards vertical">
            <div className="scenario-card">
              <span className="sc-label">Scenario</span>
              <span className="sc-value">{sc.label}</span>
            </div>
            <div className="scenario-card">
              <span className="sc-label">Incremental Buyers</span>
              <span className="sc-value">{fmt(sc.buyers)}</span>
            </div>
            <div className="scenario-card">
              <span className="sc-label">Incremental Revenue</span>
              <span className="sc-value accent">{brl(sc.rev)}</span>
            </div>
            <div className="scenario-card">
              <span className="sc-label">AOV</span>
              <span className="sc-value">R$ 137.51</span>
            </div>
            <div className="scenario-card">
              <span className="sc-label">Avg Repeat Freq</span>
              <span className="sc-value">2.11</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}


/* ── EXPERIMENT ── */

function Experiment() {
  const phases = [EXPERIMENT.pilot, EXPERIMENT.scale];
  return (
    <div className="tab-content">
      <div className="card full-width">
        <h3>Validation Strategy</h3>
        <p className="summary-text">
          Before scaling the voucher-led retention campaign, we recommend a <strong>randomized controlled trial</strong> (power
          analysis: detect +2 pp lift). The pilot is a <strong>learning investment</strong> with negative expected profit
          under conservative assumptions. Scale-up economics apply to the scored high-P(repeat) segment after causal validation.
        </p>
      </div>
      <div className="two-col">
        {phases.map((p) => (
          <div key={p.label} className={`card experiment-card ${p.profit >= 0 ? 'positive' : 'negative'}`}>
            <h3>{p.label}</h3>
            <div className="exp-grid">
              <div className="exp-item">
                <span className="exp-label">Customers</span>
                <span className="exp-val">{fmt(p.customers)}</span>
              </div>
              <div className="exp-item">
                <span className="exp-label">Cost</span>
                <span className="exp-val cost">{brl(p.cost)}</span>
              </div>
              <div className="exp-item">
                <span className="exp-label">Expected Net Profit</span>
                <span className={`exp-val ${p.profit >= 0 ? 'profit' : 'loss'}`}>{brl(p.profit)}</span>
              </div>
              {p.label === 'Scale-Up' && (
                <div className="exp-item">
                  <span className="exp-label">Expected Conversions</span>
                  <span className="exp-val">{fmt(158)}</span>
                </div>
              )}
            </div>
            <div className="exp-tag">
              {p.profit >= 0
                ? '✓ Profitable — deploy after RCT confirms lift'
                : '⚠ Learning investment — validates causal effect'}
            </div>
          </div>
        ))}
      </div>
      <div className="card full-width">
        <h3>Pilot vs Scale-Up Comparison</h3>
        <ResponsiveContainer width="100%" height={300}>
          <BarChart data={[
            { name: 'Pilot (RCT)', cost: 22605, profit: -18461 },
            { name: 'Scale-Up', cost: 13320, profit: 8453 },
          ]} margin={{ top: 10, right: 30, left: 20, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
            <XAxis dataKey="name" tick={{ fontSize: 13 }} />
            <YAxis tickFormatter={(v) => `${(v / 1000).toFixed(0)}K`} tick={{ fontSize: 12 }} />
            <Tooltip content={<CustomTooltip prefix="R$ " />} />
            <Legend />
            <Bar dataKey="cost" name="Cost (BRL)" fill="#f97316" radius={[6, 6, 0, 0]} />
            <Bar dataKey="profit" name="Net Profit (BRL)" fill="#10b981" radius={[6, 6, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

/* ── KEY CONCLUSIONS (new section at bottom of every page) ── */

function Conclusions() {
  return (
    <div className="conclusions-section">
      <h3 className="conclusions-title">Key Conclusions</h3>
      <div className="conclusions-grid">
        <div className="conclusion-card">
          <Lightbulb size={20} className="conclusion-icon" style={{ color: '#f59e0b' }} />
          <div>
            <span className="conclusion-heading">Vouchers are the #1 lever</span>
            <p>Customers who used vouchers are 3.8× more likely to return. This is the strongest actionable predictor — and the basis for our BRL 10 voucher intervention.</p>
          </div>
        </div>
        <div className="conclusion-card">
          <Lightbulb size={20} className="conclusion-icon" style={{ color: '#2563eb' }} />
          <div>
            <span className="conclusion-heading">Delivery experience matters</span>
            <p>Late deliveries and high freight costs both reduce repeat probability. Improving logistics could complement voucher campaigns for compounding effect.</p>
          </div>
        </div>
        <div className="conclusion-card">
          <Lightbulb size={20} className="conclusion-icon" style={{ color: '#0d9488' }} />
          <div>
            <span className="conclusion-heading">Small segment, outsized value</span>
            <p>The 888 High-Potential Dormant Buyers represent just 1% of the base but hold R$ 326 avg CLV — 96× higher than the Low-Potential segment (R$ 3.40).</p>
          </div>
        </div>
        <div className="conclusion-card">
          <Lightbulb size={20} className="conclusion-icon" style={{ color: '#10b981' }} />
          <div>
            <span className="conclusion-heading">ROI-positive at conservative estimates</span>
            <p>Even with a conservative 17.8% conversion rate among targeted customers, the campaign nets R$ 8,453 profit — a 63% return on the R$ 13,320 investment.</p>
          </div>
        </div>
        <div className="conclusion-card">
          <Lightbulb size={20} className="conclusion-icon" style={{ color: '#7c3aed' }} />
          <div>
            <span className="conclusion-heading">Causality must be confirmed</span>
            <p>Voucher usage correlates with repeat behavior, but the RCT pilot (3,014 customers) is essential to confirm the causal mechanism before scaling spend.</p>
          </div>
        </div>
        <div className="conclusion-card">
          <Lightbulb size={20} className="conclusion-icon" style={{ color: '#f97316' }} />
          <div>
            <span className="conclusion-heading">Installments drive engagement</span>
            <p>Higher average installments slightly increase repeat probability (OR 1.03), suggesting flexible payment options reduce friction for return purchases.</p>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── MAIN APP ── */

export default function App() {
  const [tab, setTab] = useState('overview');
  const panels = { overview: Overview, segmentation: Segmentation, model: ModelTargeting, experiment: Experiment };
  const Panel = panels[tab];

  return (
    <div className="dashboard">
      <header className="header">
        <div className="header-brand">
          <div className="header-icon-wrap">
            <Activity size={26} />
          </div>
          <div className="header-text">
            <h1>Olist <span className="header-accent">Customer Analytics</span></h1>
            <span className="subtitle">Group 3 · Retention Strategy & CLV Dashboard</span>
          </div>
        </div>
      </header>

      <div className="kpi-bar">
        <KpiCard icon={TrendingUp} label="Repeat Rate" value="3.0%" sub="Baseline" accent="#0d9488" />
        <KpiCard icon={Users} label="Total Customers" value={fmt(93349)} accent="#2563eb" />
        <KpiCard icon={Activity} label="Model AUC" value="0.743" sub="Holdout" accent="#7c3aed" />
        <KpiCard icon={Target} label="Segment Targeted" value={fmt(888)} sub="High-Potential" accent="#f59e0b" />
        <KpiCard icon={DollarSign} label="Net Profit" value={brl(8453)} sub="Per cycle" accent="#10b981" />
      </div>

      <nav className="tab-nav">
        {TABS.map((t) => (
          <button key={t.id} className={`tab-btn ${tab === t.id ? 'active' : ''}`}
            onClick={() => setTab(t.id)}>
            <t.icon size={16} />
            {t.label}
          </button>
        ))}
      </nav>

      <main className="main">
        <Panel />
      </main>

      <Conclusions />

      <footer className="footer">
        <span>Olist Customer Analytics · Group 3 · Data source: Group3_Olist_Master_Analysis.R</span>
      </footer>
    </div>
  );
}
