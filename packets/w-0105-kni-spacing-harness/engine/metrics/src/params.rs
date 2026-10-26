//! Master parameters for the metrics engine.

/// Parameters of one master, expressed in PLANE units.
///
/// On the raster plane these are capture pixels (the measured upm and
/// x-height of the render). The baseline formula is unit/scale-invariant:
/// scaling every input by s scales the resulting sidebearings by s (covered
/// by tests), so results stay comparable across capture scales.
#[derive(Debug, Clone, Copy)]
pub struct MasterParams {
    /// Units per em of the render (plane units).
    pub upm: f64,
    /// Measured x-height (plane units).
    pub x_height: f64,
    /// Baseline position (plane units; raster: row index of the baseline,
    /// y down). Only used when italic_angle_deg != 0, as the deslant pivot
    /// reference: mline = baseline_y - x_height/2.
    pub baseline_y: f64,
    /// Italic angle in degrees; 0 for upright masters.
    pub italic_angle_deg: f64,
    /// Target inter-letter white area, in thousands of square units at
    /// 1000 upm (published default 400; typical text range 200-400).
    pub param_area: f64,
    /// Depth into open counters, percent of x-height (published default 15).
    pub param_depth_pct: f64,
    /// Vertical overshoot beyond the reference bounds, percent of x-height
    /// (published default 0).
    pub param_over_pct: f64,
    /// Vertical scan step in plane units (published default 5).
    pub freq: i64,
    /// Category multiplier on `param_area` (published rule factor; 1.0 = no
    /// category adjustment). Category resolution arrives with side_classes.
    pub area_factor: f64,
}

impl Default for MasterParams {
    fn default() -> Self {
        Self {
            upm: 1000.0,
            x_height: 500.0,
            baseline_y: 0.0,
            italic_angle_deg: 0.0,
            param_area: 400.0,
            param_depth_pct: 15.0,
            param_over_pct: 0.0,
            freq: 5,
            area_factor: 1.0,
        }
    }
}

impl MasterParams {
    /// Area parameter after the category factor (published: effectiveArea).
    pub fn effective_area(&self) -> f64 {
        self.param_area * self.area_factor
    }

    /// Vertical overshoot in plane units (published: xHeight * paramOver/100).
    pub fn overshoot(&self) -> f64 {
        self.x_height * self.param_over_pct / 100.0
    }
}
