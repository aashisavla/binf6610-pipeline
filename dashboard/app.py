"""dashboard/app.py — a two-page Dash app over the runs database (Assignment 9's db/).

    python3 dashboard/app.py runs.db [port]      # then open http://127.0.0.1:8050

/                      the runs: db/queries/q1.sql, with a link to each run's results
/results?run=<run_id>  one run: its samples, five plots, and its sites; a click on a bar
                       of a count plot leaves in the sites table only that bar's sites
"""
import os
import sqlite3
import sys
from urllib.parse import parse_qs, quote

import dash_ag_grid as dag
import pandas as pd
import plotly.express as px
from dash import Dash, Input, Output, State, ctx, dcc, html, no_update

DB = sys.argv[1] if len(sys.argv) > 1 else "runs.db"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8050
HERE = os.path.dirname(os.path.abspath(__file__))
TRANSITIONS = {("A", "G"), ("G", "A"), ("C", "T"), ("T", "C")}


# ---------------------------------------------------------------- data
def query(sql, params=()):
    """Run one query on the database named on the command line. Each call opens its own
    connection: Dash runs every callback in a thread of its own."""
    con = sqlite3.connect(DB)
    try:
        return pd.read_sql_query(sql, con, params=params)
    finally:
        con.close()


def runs_table():
    with open(os.path.join(HERE, "..", "db", "queries", "q1.sql")) as fh:
        return query(fh.read())


def run_samples(run_id):
    return query(
        "SELECT rs.sample_id, rs.condition, s.phenotype, s.is_synthetic_phenotype "
        "FROM run_samples rs JOIN samples s ON s.sample_id = rs.sample_id "
        "WHERE rs.run_id = ? ORDER BY rs.sample_id", (run_id,))


def variant_type(ref, alt):
    """multiallelic if alt holds a comma; SNP if ref and alt are one base each; else indel."""
    if "," in alt:
        return "multiallelic"
    if len(ref) == 1 and len(alt) == 1:
        return "SNP"
    return "indel"


def titv(ref, alt):
    return "transition" if (ref.upper(), alt.upper()) in TRANSITIONS else "transversion"


def run_sites(run_id):
    """Every site of the run, with its type and, for SNPs, transition or transversion."""
    df = query("SELECT chrom, pos, ref, alt, qual, filter FROM variants WHERE run_id = ?",
               (run_id,))
    df["type"] = [variant_type(r, a) for r, a in zip(df["ref"], df["alt"])]
    df["titv"] = [titv(r, a) if t == "SNP" else None
                  for r, a, t in zip(df["ref"], df["alt"], df["type"])]
    return df


SITE_COLUMNS = ["chrom", "pos", "ref", "alt", "qual", "filter"]


def records(df, columns=None):
    """Rows for an AG Grid, with NaN written as null."""
    df = df[columns] if columns else df
    return df.astype(object).where(pd.notna(df), None).to_dict("records")


def counts(series, name):
    c = series.value_counts().rename_axis(name).reset_index(name="sites")
    return c.sort_values(name).reset_index(drop=True)


# ---------------------------------------------------------------- pages
def grid(id_, df):
    return dag.AgGrid(id=id_, rowData=records(df),
                      columnDefs=[{"field": c} for c in df.columns],
                      columnSize="sizeToFit", dashGridOptions={"pagination": True})


def runs_page():
    runs = runs_table()
    links = html.Ul([html.Li(dcc.Link(r, href=f"/results?run={quote(r)}"))
                     for r in runs["run_id"]])
    return html.Div([
        html.H1("Runs of the variant-call pipeline"),
        html.P("Open a run's results:"),
        links,
        grid("runs-table", runs),
    ])


def results_page(run_id):
    sites = run_sites(run_id)
    samples = run_samples(run_id)
    snps = sites[sites["type"] == "SNP"]

    f_counts = counts(sites["filter"], "filter")
    plot_filter = px.bar(f_counts, x="filter", y="sites",
                         title="How many sites passed, and why did the others fail?")
    plot_qual = px.histogram(sites, x="qual", nbins=60, title="How confident are the calls?")
    plot_position = px.histogram(sites, x="pos", nbins=60,
                                 title="Where along the region are the sites?")
    plot_type = px.bar(counts(sites["type"], "type"), x="type", y="sites",
                       title="How many SNPs, indels and multiallelic sites?")
    plot_titv = px.bar(counts(snps["titv"], "titv"), x="titv", y="sites",
                       title="Among SNPs, how many transitions and transversions?")

    return html.Div([
        dcc.Link("← all runs", href="/"),
        html.H1(f"Run {run_id}"),
        html.H2("Samples"),
        html.P("The phenotypes are synthetic, made up for the course: "
               "see is_synthetic_phenotype. They are not findings."),
        grid("samples-table", samples),
        html.H2("Sites"),
        html.P("Click a bar of the filter, type or Ti/Tv plot to list only that bar's sites."),
        html.Div([
            dcc.Graph(id="plot-filter", figure=plot_filter),
            dcc.Graph(id="plot-type", figure=plot_type),
            dcc.Graph(id="plot-titv", figure=plot_titv),
            dcc.Graph(id="plot-qual", figure=plot_qual),
            dcc.Graph(id="plot-position", figure=plot_position),
        ]),
        grid("sites-table", sites[SITE_COLUMNS]),
    ])


# ---------------------------------------------------------------- app
app = Dash(__name__, suppress_callback_exceptions=True)
app.title = "variant-call runs"
app.layout = html.Div([dcc.Location(id="url"), html.Div(id="page")])


def run_from(search):
    return parse_qs((search or "").lstrip("?")).get("run", [None])[0]


@app.callback(Output("page", "children"), Input("url", "pathname"), Input("url", "search"))
def draw_page(pathname, search):
    if pathname == "/results":
        run_id = run_from(search)
        if run_id is None:
            return html.P("No run given: /results?run=<run_id>")
        return results_page(run_id)
    return runs_page()


@app.callback(Output("sites-table", "rowData"),
              Input("plot-filter", "clickData"),
              Input("plot-type", "clickData"),
              Input("plot-titv", "clickData"),
              State("url", "search"),
              prevent_initial_call=True)
def narrow_sites(filter_click, type_click, titv_click, search):
    clicks = {"plot-filter": filter_click, "plot-type": type_click, "plot-titv": titv_click}
    click = clicks.get(ctx.triggered_id)
    if not click:
        return no_update
    point = click["points"][0]
    label = point.get("label", point.get("x"))
    sites = run_sites(run_from(search))
    column = {"plot-filter": "filter", "plot-type": "type", "plot-titv": "titv"}[ctx.triggered_id]
    return records(sites[sites[column] == label], SITE_COLUMNS)


if __name__ == "__main__":
    app.run(port=PORT, debug=True)
