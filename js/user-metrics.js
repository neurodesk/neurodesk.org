(function () {
  var SVG_NS = "http://www.w3.org/2000/svg";
  var MONTH_NAMES = ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"];
  var MONTH_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

  function formatNumber(value) {
    return new Intl.NumberFormat().format(Number(value || 0));
  }

  function monthLabel(month, short) {
    var parts = month.split("-");
    var names = short ? MONTH_SHORT : MONTH_NAMES;
    var name = names[Number(parts[1]) - 1] || parts[1];
    return name + " " + parts[0];
  }

  function formatDate(value) {
    if (!value) {
      return "";
    }
    var date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "";
    }
    return date.toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
      timeZone: "UTC"
    });
  }

  function svgEl(name, attrs) {
    var el = document.createElementNS(SVG_NS, name);
    Object.keys(attrs || {}).forEach(function (key) {
      el.setAttribute(key, attrs[key]);
    });
    return el;
  }

  function niceStep(rough) {
    var magnitude = Math.pow(10, Math.floor(Math.log10(rough)));
    var candidates = [1, 2, 2.5, 5, 10];
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i] * magnitude >= rough) {
        return candidates[i] * magnitude;
      }
    }
    return 10 * magnitude;
  }

  function renderSummary(data, currentMonthKey) {
    var summary = document.createElement("div");
    summary.className = "user-metrics__summary";

    var metric = document.createElement("span");
    metric.className = "user-metrics__metric";
    var number = document.createElement("strong");
    number.textContent = formatNumber(data.totalUsers);
    var label = document.createElement("span");
    label.textContent = "users to date";
    metric.append(number, label);
    summary.append(metric);

    var details = document.createElement("span");
    details.className = "user-metrics__details";
    details.textContent = "Source: " + (data.source || "Google Analytics");
    var generatedAt = formatDate(data.generatedAt);
    if (generatedAt) {
      details.textContent += " · updated " + generatedAt;
    }
    summary.append(details);
    return summary;
  }

  function renderChart(months) {
    var width = 720;
    var height = 320;
    var margin = { top: 24, right: 20, bottom: 34, left: 8 };
    var maxValue = months[months.length - 1].cumulativeUsers;
    var step = niceStep(Math.max(maxValue, 1) / 4);
    var yMax = Math.ceil(maxValue / step) * step;

    // Left margin grows with the widest y tick label.
    margin.left = 16 + 8 * String(formatNumber(yMax)).length;

    var plotWidth = width - margin.left - margin.right;
    var plotHeight = height - margin.top - margin.bottom;

    function x(index) {
      return months.length > 1
        ? margin.left + (plotWidth * index) / (months.length - 1)
        : margin.left + plotWidth / 2;
    }
    function y(value) {
      return margin.top + plotHeight - (plotHeight * value) / yMax;
    }

    var figure = document.createElement("figure");
    figure.className = "user-metrics__chart";
    figure.setAttribute("tabindex", "0");
    figure.setAttribute(
      "aria-label",
      "Cumulative Neurodesk users over time, reaching " +
        formatNumber(maxValue) + " in " + monthLabel(months[months.length - 1].month) +
        ". Monthly values are in the table below."
    );

    var svg = svgEl("svg", {
      viewBox: "0 0 " + width + " " + height,
      role: "img",
      "aria-hidden": "true"
    });

    // Horizontal gridlines with y tick labels.
    for (var value = 0; value <= yMax; value += step) {
      svg.append(svgEl("line", {
        x1: margin.left, x2: width - margin.right,
        y1: y(value), y2: y(value),
        class: value === 0 ? "user-metrics__baseline" : "user-metrics__gridline"
      }));
      var tick = svgEl("text", {
        x: margin.left - 8, y: y(value) + 4,
        "text-anchor": "end",
        class: "user-metrics__tick"
      });
      tick.textContent = formatNumber(value);
      svg.append(tick);
    }

    // X ticks: each January when the range spans years, otherwise evenly spaced.
    var spansYears = months.length >= 20;
    var stride = Math.max(1, Math.ceil(months.length / 8));
    months.forEach(function (entry, index) {
      var parts = entry.month.split("-");
      var isTick = spansYears ? parts[1] === "01" : index % stride === 0;
      if (!isTick) {
        return;
      }
      var label = svgEl("text", {
        x: x(index), y: height - margin.bottom + 22,
        "text-anchor": "middle",
        class: "user-metrics__tick"
      });
      label.textContent = spansYears
        ? parts[0]
        : MONTH_SHORT[Number(parts[1]) - 1] + " " + parts[0].slice(2);
      svg.append(label);
    });

    var linePoints = months.map(function (entry, index) {
      return x(index) + " " + y(entry.cumulativeUsers);
    });
    svg.append(svgEl("path", {
      d: "M " + linePoints.join(" L ") +
        " L " + x(months.length - 1) + " " + y(0) +
        " L " + x(0) + " " + y(0) + " Z",
      class: "user-metrics__area"
    }));
    svg.append(svgEl("path", {
      d: "M " + linePoints.join(" L "),
      class: "user-metrics__line"
    }));

    // Crosshair (hidden until hover) and end marker with a surface ring.
    var crosshair = svgEl("line", {
      y1: margin.top, y2: height - margin.bottom,
      class: "user-metrics__crosshair"
    });
    crosshair.style.display = "none";
    svg.append(crosshair);

    var hoverDot = svgEl("circle", { r: 5, class: "user-metrics__dot" });
    hoverDot.style.display = "none";
    svg.append(hoverDot);

    var lastIndex = months.length - 1;
    svg.append(svgEl("circle", {
      cx: x(lastIndex), cy: y(maxValue), r: 5,
      class: "user-metrics__dot"
    }));
    var endLabel = svgEl("text", {
      x: x(lastIndex) - 8, y: y(maxValue) - 10,
      "text-anchor": "end",
      class: "user-metrics__end-label"
    });
    endLabel.textContent = formatNumber(maxValue) + " users";
    svg.append(endLabel);

    figure.append(svg);

    // Tooltip: month heading, then value-first rows.
    var tooltip = document.createElement("div");
    tooltip.className = "user-metrics__tooltip";
    tooltip.style.display = "none";
    var tooltipTitle = document.createElement("div");
    tooltipTitle.className = "user-metrics__tooltip-title";
    var cumulativeRow = document.createElement("div");
    cumulativeRow.className = "user-metrics__tooltip-row";
    var cumulativeKey = document.createElement("span");
    cumulativeKey.className = "user-metrics__tooltip-key";
    var cumulativeValue = document.createElement("strong");
    var cumulativeLabel = document.createElement("span");
    cumulativeLabel.textContent = "users total";
    cumulativeRow.append(cumulativeKey, cumulativeValue, cumulativeLabel);
    var newRow = document.createElement("div");
    newRow.className = "user-metrics__tooltip-row";
    var newKey = document.createElement("span");
    newKey.className = "user-metrics__tooltip-key user-metrics__tooltip-key--blank";
    var newValue = document.createElement("strong");
    var newLabel = document.createElement("span");
    newLabel.textContent = "new that month";
    newRow.append(newKey, newValue, newLabel);
    tooltip.append(tooltipTitle, cumulativeRow, newRow);
    figure.append(tooltip);

    function showIndex(index) {
      var entry = months[index];
      var px = x(index);
      crosshair.setAttribute("x1", px);
      crosshair.setAttribute("x2", px);
      crosshair.style.display = "";
      hoverDot.setAttribute("cx", px);
      hoverDot.setAttribute("cy", y(entry.cumulativeUsers));
      hoverDot.style.display = "";

      tooltipTitle.textContent = monthLabel(entry.month);
      cumulativeValue.textContent = formatNumber(entry.cumulativeUsers);
      newValue.textContent = formatNumber(entry.newUsers);
      tooltip.style.display = "";

      var rect = figure.getBoundingClientRect();
      var scale = rect.width / width;
      var left = px * scale + 12;
      if (left + tooltip.offsetWidth + 8 > rect.width) {
        left = px * scale - tooltip.offsetWidth - 12;
      }
      tooltip.style.left = Math.max(0, left) + "px";
      tooltip.style.top = Math.max(0, y(entry.cumulativeUsers) * scale - 8) + "px";
    }

    function hide() {
      crosshair.style.display = "none";
      hoverDot.style.display = "none";
      tooltip.style.display = "none";
    }

    var focusIndex = lastIndex;
    svg.addEventListener("pointermove", function (event) {
      var rect = svg.getBoundingClientRect();
      var px = ((event.clientX - rect.left) / rect.width) * width;
      var ratio = (px - margin.left) / (plotWidth || 1);
      var index = Math.round(ratio * (months.length - 1));
      focusIndex = Math.min(months.length - 1, Math.max(0, index));
      showIndex(focusIndex);
    });
    svg.addEventListener("pointerleave", hide);
    figure.addEventListener("focus", function () {
      showIndex(focusIndex);
    });
    figure.addEventListener("blur", hide);
    figure.addEventListener("keydown", function (event) {
      if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
        event.preventDefault();
        focusIndex = event.key === "ArrowLeft"
          ? Math.max(0, focusIndex - 1)
          : Math.min(months.length - 1, focusIndex + 1);
        showIndex(focusIndex);
      }
    });

    return figure;
  }

  var MAP_RAMP = ["#e6f1d6", "#d3e7b6", "#b7d886", "#6aa329", "#4f7b38"];

  function binThresholds(values) {
    // Quantile bin edges over countries with data; deduped for small sets.
    var sorted = values.slice().sort(function (a, b) { return a - b; });
    var thresholds = [];
    for (var i = 1; i < MAP_RAMP.length; i++) {
      var value = sorted[Math.min(sorted.length - 1,
        Math.floor((sorted.length * i) / MAP_RAMP.length))];
      if (!thresholds.length || value > thresholds[thresholds.length - 1]) {
        thresholds.push(value);
      }
    }
    return thresholds;
  }

  function binIndex(value, thresholds) {
    for (var i = 0; i < thresholds.length; i++) {
      if (value < thresholds[i]) {
        return i;
      }
    }
    return thresholds.length;
  }

  function legendItem(color, text, isSwatchOutlined) {
    var item = document.createElement("span");
    item.className = "user-metrics__legend-item";
    var swatch = document.createElement("span");
    swatch.className = "user-metrics__legend-swatch" +
      (isSwatchOutlined ? " user-metrics__legend-swatch--nodata" : "");
    swatch.style.background = color;
    var label = document.createElement("span");
    label.textContent = text;
    item.append(swatch, label);
    return item;
  }

  function renderMapInto(figure, svgText, countries) {
    var doc = new DOMParser().parseFromString(svgText, "image/svg+xml");
    var svg = doc.documentElement;
    if (!svg || svg.nodeName !== "svg") {
      throw new Error("Invalid map SVG");
    }
    svg.removeAttribute("width");
    svg.removeAttribute("height");
    svg.setAttribute("class", "user-metrics__map-svg");
    svg.setAttribute("aria-hidden", "true");

    var byCode = new Map(countries.map(function (entry) {
      return [entry.code.toLowerCase(), entry];
    }));
    var thresholds = binThresholds(countries.map(function (entry) {
      return entry.users;
    }));

    svg.querySelectorAll("path[id]").forEach(function (path) {
      var entry = byCode.get(path.id.toLowerCase());
      if (entry) {
        path.style.fill = MAP_RAMP[binIndex(entry.users, thresholds)];
      }
    });

    figure.textContent = "";
    var caption = document.createElement("figcaption");
    caption.className = "user-metrics__map-caption";
    caption.textContent = "Cumulative users by country (all time)";
    figure.append(caption, svg);

    // Legend: one swatch per bin range, plus the no-data fill.
    var maxUsers = countries.reduce(function (max, entry) {
      return Math.max(max, entry.users);
    }, 0);
    var legend = document.createElement("div");
    legend.className = "user-metrics__legend";
    var lower = 1;
    for (var i = 0; i <= thresholds.length; i++) {
      var upper = i < thresholds.length ? thresholds[i] - 1 : maxUsers;
      if (upper < lower) {
        continue;
      }
      legend.append(legendItem(
        MAP_RAMP[i],
        lower === upper ? formatNumber(lower) : formatNumber(lower) + "–" + formatNumber(upper)
      ));
      lower = upper + 1;
    }
    legend.append(legendItem("transparent", "No data", true));
    figure.append(legend);

    var tooltip = document.createElement("div");
    tooltip.className = "user-metrics__tooltip";
    tooltip.style.display = "none";
    var tooltipTitle = document.createElement("div");
    tooltipTitle.className = "user-metrics__tooltip-title";
    var row = document.createElement("div");
    row.className = "user-metrics__tooltip-row";
    var value = document.createElement("strong");
    var label = document.createElement("span");
    row.append(value, label);
    tooltip.append(tooltipTitle, row);
    figure.append(tooltip);

    var hovered = null;
    function clearHover() {
      if (hovered) {
        hovered.classList.remove("user-metrics__country--hover");
        hovered = null;
      }
      tooltip.style.display = "none";
    }
    svg.addEventListener("pointermove", function (event) {
      var path = event.target.closest ? event.target.closest("path[id]") : null;
      if (!path) {
        clearHover();
        return;
      }
      if (hovered !== path) {
        if (hovered) {
          hovered.classList.remove("user-metrics__country--hover");
        }
        hovered = path;
        hovered.classList.add("user-metrics__country--hover");
      }
      var entry = byCode.get(path.id.toLowerCase());
      tooltipTitle.textContent = (entry && entry.name) ||
        path.getAttribute("aria-label") || path.getAttribute("name") || path.id.toUpperCase();
      value.textContent = entry ? formatNumber(entry.users) : "0";
      label.textContent = entry ? "users" : "recorded users";
      tooltip.style.display = "";
      var rect = figure.getBoundingClientRect();
      var left = event.clientX - rect.left + 14;
      if (left + tooltip.offsetWidth + 8 > rect.width) {
        left = event.clientX - rect.left - tooltip.offsetWidth - 14;
      }
      tooltip.style.left = Math.max(0, left) + "px";
      tooltip.style.top = (event.clientY - rect.top - tooltip.offsetHeight - 10) + "px";
    });
    svg.addEventListener("pointerleave", clearHover);
  }

  function renderMap(countries, mapUrl) {
    var section = document.createElement("div");
    section.className = "user-metrics__map";

    var figure = document.createElement("figure");
    figure.className = "user-metrics__map-figure";
    figure.setAttribute(
      "aria-label",
      "World map of cumulative Neurodesk users by country since tracking began. Values are listed in the table below the map."
    );
    var status = document.createElement("span");
    status.className = "user-metrics__status";
    status.textContent = "Loading map...";
    figure.append(status);
    section.append(figure);

    var details = document.createElement("details");
    var summary = document.createElement("summary");
    summary.textContent = "Cumulative users by country (table)";
    details.append(summary);
    var wrapper = document.createElement("div");
    wrapper.className = "user-metrics__table-wrapper";
    var table = document.createElement("table");
    table.className = "user-metrics__table td-initial";
    var head = document.createElement("thead");
    var headRow = document.createElement("tr");
    ["Country", "Users"].forEach(function (text, index) {
      var th = document.createElement("th");
      th.textContent = text;
      th.scope = "col";
      if (index > 0) {
        th.className = "user-metrics__num";
      }
      headRow.append(th);
    });
    head.append(headRow);
    table.append(head);
    var body = document.createElement("tbody");
    countries.forEach(function (entry) {
      var tr = document.createElement("tr");
      var nameCell = document.createElement("th");
      nameCell.scope = "row";
      nameCell.textContent = entry.name;
      var usersCell = document.createElement("td");
      usersCell.className = "user-metrics__num";
      usersCell.textContent = formatNumber(entry.users);
      tr.append(nameCell, usersCell);
      body.append(tr);
    });
    table.append(body);
    wrapper.append(table);
    details.append(wrapper);
    section.append(details);

    fetch(mapUrl, { credentials: "same-origin" })
      .then(function (response) {
        if (!response.ok) {
          throw new Error("Map request failed: " + response.status);
        }
        return response.text();
      })
      .then(function (svgText) {
        renderMapInto(figure, svgText, countries);
      })
      .catch(function () {
        status.textContent = "The map could not be loaded.";
      });

    return section;
  }

  function renderTable(months, currentMonthKey) {
    var wrapper = document.createElement("div");
    wrapper.className = "user-metrics__table-wrapper";

    var table = document.createElement("table");
    table.className = "user-metrics__table td-initial";

    var caption = document.createElement("caption");
    caption.textContent = "New users acquired each month";
    table.append(caption);

    var head = document.createElement("thead");
    var headRow = document.createElement("tr");
    ["Month", "New users", "Cumulative users"].forEach(function (text, index) {
      var th = document.createElement("th");
      th.textContent = text;
      th.scope = "col";
      if (index > 0) {
        th.className = "user-metrics__num";
      }
      headRow.append(th);
    });
    head.append(headRow);
    table.append(head);

    var body = document.createElement("tbody");
    months.slice().reverse().forEach(function (entry) {
      var row = document.createElement("tr");
      var monthCell = document.createElement("th");
      monthCell.scope = "row";
      monthCell.textContent = monthLabel(entry.month) +
        (entry.month === currentMonthKey ? " (in progress)" : "");
      var newCell = document.createElement("td");
      newCell.className = "user-metrics__num";
      newCell.textContent = formatNumber(entry.newUsers);
      var cumulativeCell = document.createElement("td");
      cumulativeCell.className = "user-metrics__num";
      cumulativeCell.textContent = formatNumber(entry.cumulativeUsers);
      row.append(monthCell, newCell, cumulativeCell);
      body.append(row);
    });
    table.append(body);
    wrapper.append(table);
    return wrapper;
  }

  function renderStatus(block, message) {
    block.textContent = "";
    var status = document.createElement("span");
    status.className = "user-metrics__status";
    status.textContent = message;
    block.append(status);
  }

  function render(block, data) {
    if (data.unavailable || !Array.isArray(data.months) || !data.months.length) {
      renderStatus(block, "User statistics are not available in this build.");
      return;
    }
    var currentMonthKey = String(data.generatedAt || "").slice(0, 7);
    block.textContent = "";
    block.append(
      renderSummary(data, currentMonthKey),
      renderChart(data.months)
    );
    if (Array.isArray(data.countries) && data.countries.length && block.dataset.userMetricsMap) {
      block.append(renderMap(data.countries, block.dataset.userMetricsMap));
    }
    block.append(renderTable(data.months, currentMonthKey));
  }

  var blocks = document.querySelectorAll("[data-user-metrics-url]");
  if (!blocks.length) {
    return;
  }

  fetch(blocks[0].dataset.userMetricsUrl, { credentials: "same-origin" })
    .then(function (response) {
      if (!response.ok) {
        throw new Error("User statistics request failed: " + response.status);
      }
      return response.json();
    })
    .then(function (data) {
      blocks.forEach(function (block) {
        render(block, data);
      });
    })
    .catch(function () {
      blocks.forEach(function (block) {
        renderStatus(block, "User statistics could not be loaded.");
      });
    });
}());
