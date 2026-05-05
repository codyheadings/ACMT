# AssembloidCellMigrationTracker (ACMT)
Open-source pipeline for 4D cell tracking and migration analysis in iPSC-derived assembloid live imaging.

Tracking pipeline scripts are located here. For annotated cell tracking data, navigate to the 'tracking-data' branch of this repository (or click this <a href="https://github.com/codyheadings/ACMT/tree/tracking-data">link</a>).

<h3>Pipeline Operation</h3>
    <hr>

<h4>Step 1 - Preprocess Raw Imaging Data</h4>
    <p>
        Begin with raw microscopy files (e.g., Nikon <code>.nd2</code>). Use 
        <a href="#preProcessND2"><code>preProcessND2</code></a> to extract a specific series/channel combination, apply optional 
        spatial binning, and perform Gaussian background subtraction. Save to a shared tracking folder.
    </p>
    <p>
        The output is a cleaned BigTIFF file suitable for manual cell tracking.
    </p>

<pre class="codeblock"><code>preProcessND2(<span class="string">"data/example.nd2"</span>, <span class="string">"output"</span>, ...
    SeriesIndex=1, ChannelIndex=2);
</code></pre>

<h4>Step 2 - Perform Manual Cell Tracking (External)</h4>
    <p>
        Load the processed TIFF into ImageJ (or equivalent image software) and perform 
        cell tracking using OrthoTrack, saving cell trajectories as ROIs. 
        Export saved results as <code>Results.csv</code>.
    </p>
    <p>
        Each tracker's data should be stored in their own folder. Example:
    </p>

<pre class="codeblock"><code>rootFolder/
├── Channel1/
│   ├── Dataset1/
│   │   ├── Series1/
│   │   │   ├── Tracker1/
│   │   │   │   └── Results.csv
│   │   │   ├── Tracker2/
│   │   │   │   └── Results.csv
</code></pre>

<h4>Step 3 - Collect Tracking Data</h4>
    <p>
        When all cells have been tracked across all images, use <a href="#collectTrackingData"><code>collectTrackingData</code></a>
        to combine all tracking outputs into a single table. 
        This step and the following ones can be performed on our tracking coordinate data, located <a target="_blank" href="https://github.com/codyheadings/ACMT/tree/tracking-data">here</a>.
    </p>
    <p>
        Folder names are automatically converted into grouping variables 
        (<code>Group1</code>, <code>Group2</code>, etc.).
    </p>

<pre class="codeblock"><code>tracks = collectTrackingData(<span class="string">"example"</span>, ...
    XYScale=0.65, ZScale=20, TScale=30);
</code></pre>

<h4>Step 4 - (Optional) Remove Duplicate Tracks</h4>
    <p>
        If multiple trackers labeled the same cells, you can use 
        <a href="#filterDuplicateTracks"><code>filterDuplicateTracks</code></a> to remove redundant trajectories 
        based on detected spatial overlap. This is not essential and there are some cases
        where you may want to leave the data unfiltered.
    </p>

<pre class="codeblock"><code>tracks = filterDuplicateTracks(tracks);
</code></pre>

<h4>Step 5 - Compute Cell Metrics</h4>
    <p>
        Run <a href="#computeTrackingMetrics"><code>computeTrackingMetrics</code></a> to calculate per-cell movement 
        statistics, including:
    </p>
    <ul>
        <li>Speed (average, cumulative, variance)</li>
        <li>Distance (total, net displacement)</li>
        <li>Directionality ratio</li>
    </ul>

<pre class="codeblock"><code>results = computeTrackingMetrics(tracks, <span class="string">"output"</span>);
</code></pre>

<p>
    Output files are generated per top-level group (e.g., per channel).
</p>

<h4>Step 6 - Statistical Analysis</h4>
    <p>
        Use <a href="#analyzeByGroup"><code>analyzeByGroup</code></a> to compare experimental groups and 
        compute statistical significance (e.g., Shapiro-Wilk normality tests 
        and pairwise comparisons).
    </p>

<pre class="codeblock"><code>analysis = analyzeByGroup(results.C1, ...
    <span class="string">"/swtest"</span>, <span class="string">"Dataset"</span>, <span class="string">"output/analysis.xlsx"</span>);
</code></pre>

<h4>Step 7 - Additional Motion Analysis</h4>

<h5>Mean Squared Displacement (MSD)</h5>
    <p>
        Use <a href="#computeMSD"><code>computeMSD</code></a> to quantify diffusive behavior of cells.
    </p>
    <p>
        <strong>Important:</strong> This function requires the 
        <strong><a target="_blank" href="https://tinevez.github.io/msdanalyzer/">@msdanalyzer</a></strong> MATLAB toolkit (developed by 
        Jean-Yves Tinevez). Ensure it is installed and added to your MATLAB path.
    </p>

<pre class="codeblock"><code>mmsd = computeMSD(<span class="string">"tracks.xlsx"</span>, <span class="string">"output"</span>);
</code></pre>

<h5>Turning Angles</h5>
    <p>
        Use <a href="#computeTurningAngles"><code>computeTurningAngles</code></a> to measure directional changes 
        between consecutive movement steps.
    </p>

<pre class="codeblock"><code>angles = computeTurningAngles(<span class="string">"tracks.xlsx"</span>, <span class="string">"output"</span>);
</code></pre>

<h4>Step 8 - Visualization</h4>
    <p>
        Generate representative trajectory plots using 
        <a href="#plotRepresentativeGraphs"><code>plotRepresentativeGraphs</code></a>. Tracks are selected based on 
        median path length for visualization consistency.
    </p>

<pre class="codeblock"><code>plotRepresentativeGraphs(<span class="string">"example/AggregatedResults.xlsx"</span>, ...
    <span class="string">"figures"</span>, 8, 0);
</code></pre>
