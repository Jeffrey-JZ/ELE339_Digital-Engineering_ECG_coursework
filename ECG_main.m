%% ELE339/ELE346 - DSP Coursework
% ------------------------------------------------------------------------

clear; clc; close all;

%% Step 1: Load the data
load('ECGData1.mat');                  % gives origSig and noisySig
origSig  = origSig(:);                 % force column vectors
noisySig = noisySig(:);

fs = 360;                              % sampling frequency  [Hz]
N  = length(noisySig);                 % number of samples
T  = N/fs;                             % duration             [s]
t  = (0:N-1).'/fs;                     % time vector          [s]

fprintf('Samples = %d, fs = %g Hz, duration = %g s\n', N, fs, T);

%% Step 2: Plot noisySig and origSig in mV vs seconds
figure('Name','Step 2 - Time-domain signals','Color','w', ...
       'Position',[100 100 900 550]);

subplot(2,1,1);
plot(t, noisySig, 'Color',[0.75 0.22 0.17], 'LineWidth',0.7);
ylabel('Voltage (mV)');
title('Noisy ECG signal -- noisySig');
xlim([0 T]); grid on; box off;

subplot(2,1,2);
plot(t, origSig, 'Color',[0.17 0.24 0.31], 'LineWidth',0.8);
xlabel('Time (s)'); ylabel('Voltage (mV)');
title('Original ECG signal -- origSig');
xlim([0 T]); grid on; box off;

%% Step 3: Heart rate estimation (R-peak counting)
% Detect dominant positive peaks on the clean signal.  Use a 0.55*max
% threshold and a minimum spacing of 0.30 s (i.e. <= 200 bpm).
[pks, locs] = findpeaks(origSig, ...
    'MinPeakHeight',  0.55*max(origSig), ...
    'MinPeakDistance', round(0.30*fs));

nBeats = numel(locs);
bpm    = nBeats * (60/T);
fprintf('R-peaks found: %d  -->  HR = %.1f bpm\n', nBeats, bpm);

figure('Name','Step 3 - Heart rate','Color','w', ...
       'Position',[100 100 900 320]);
plot(t, origSig, 'Color',[0.17 0.24 0.31], 'LineWidth',0.8); hold on;
plot(t(locs), pks, 'o', 'MarkerFaceColor',[0.90 0.49 0.13], ...
                       'MarkerEdgeColor','none', 'MarkerSize',7);
xlabel('Time (s)'); ylabel('Voltage (mV)');
title(sprintf('Detected R-peaks  --  Heart-rate \\approx %.0f bpm', bpm));
legend('origSig', sprintf('R-peaks (%d beats in %g s)', nBeats, T), ...
       'Location','northeast'); legend boxoff;
xlim([0 T]); grid on; box off;

%% Step 4: DFT of noisySig (one-sided amplitude spectrum)
X        = fft(noisySig);
freq     = (0:N-1).' * (fs/N);
half     = 1:floor(N/2)+1;
freq_pos = freq(half);
mag_pos  = abs(X(half)) * 2/N;          % single-sided amplitude

%% Step 5 & 6: Identify the 60 Hz mains-hum peak and pick the cut-off
fMains       = 60;                      % US grid
[~, idxMain] = min(abs(freq_pos - fMains));
mainsAmp     = mag_pos(idxMain);

fc           = 40;                      % chosen cut-off  [Hz]
fc_norm      = fc/fs;                   % cycles / sample

% Auto-detect the artificial high-frequency noise band
% Search above 70 Hz so we skip the cut-off region and the 60 Hz mains
% line.  Smooth the spectrum (15-bin moving mean) to suppress single-bin
% spikes, then take the largest contiguous run that exceeds 3 x median of
% the smoothed spectrum in that search region.
search_mask = freq_pos > 70;
mag_search  = mag_pos(search_mask);
freq_search = freq_pos(search_mask);
mag_smooth  = movmean(mag_search, 15);
threshold   = 3 * median(mag_smooth);

above  = mag_smooth > threshold;
d      = diff([false; above; false]);
starts = find(d ==  1);
ends   = find(d == -1) - 1;

if ~isempty(starts)
    [~, k]   = max(ends - starts);            % longest run
    fNoiseLo = freq_search(starts(k));
    fNoiseHi = freq_search(ends(k));
    fprintf('Artificial-noise band detected:  %.1f Hz - %.1f Hz\n', ...
            fNoiseLo, fNoiseHi);
else
    fNoiseLo = NaN;  fNoiseHi = NaN;
    warning('No artificial-noise band detected.');
end

fprintf('60 Hz peak amplitude   = %.3f mV\n', mainsAmp);
fprintf('Cut-off  fc = %g Hz  =  %.4f cycles/sample\n', fc, fc_norm);

figure('Name','Step 4-6 - DFT of noisySig','Color','w', ...
       'Position',[100 100 900 420]);
plot(freq_pos, mag_pos, 'Color',[0.20 0.29 0.37], 'LineWidth',0.8); hold on;

yMax = max(mag_pos)*1.10;

% ECG band shading (0..fc) -- green
patch([0 fc fc 0], [0 0 yMax yMax], [0.15 0.68 0.38], ...
      'FaceAlpha',0.10, 'EdgeColor','none');

% Artificial-noise band shading (auto-detected) -- yellow
if ~isnan(fNoiseLo)
    patch([fNoiseLo fNoiseHi fNoiseHi fNoiseLo], [0 0 yMax yMax], ...
          [1.00 0.88 0.30], 'FaceAlpha',0.30, ...
          'EdgeColor',[0.85 0.65 0.13], 'LineStyle','--', 'LineWidth',0.8);
    text((fNoiseLo+fNoiseHi)/2, yMax*0.92, ...
         sprintf('Artificial noise\n%.0f - %.0f Hz', fNoiseLo, fNoiseHi), ...
         'Color',[0.65 0.45 0.05], 'FontWeight','bold', ...
         'HorizontalAlignment','center');
end

% Cut-off line
xline(fc, '--', sprintf('fc = %g Hz  (%.4f cyc/sample)', fc, fc_norm), ...
      'Color',[0.15 0.68 0.38], 'LineWidth',1.3, ...
      'LabelHorizontalAlignment','left');

% Mains-hum annotation
plot(freq_pos(idxMain), mainsAmp, 'o', 'MarkerSize',7, ...
     'MarkerFaceColor',[0.75 0.22 0.17], 'MarkerEdgeColor','none');
text(fMains+5, mainsAmp+yMax*0.10, ...
    sprintf('60 Hz mains hum\n(|X| = %.2f mV)', mainsAmp), ...
    'Color',[0.75 0.22 0.17]);

xlim([0 fs/2]); ylim([0 yMax]);
xlabel('Frequency (Hz)'); ylabel('|X(f)|  (mV)');
title('Magnitude spectrum of noisySig with cut-off, mains-hum peak and artificial-noise band');
grid on; box off;

% Zoom 40-80 Hz showing the mains peak more clearly
figure('Name','Step 5 zoom - 60 Hz peak','Color','w', ...
       'Position',[100 100 700 320]);
mZoom = freq_pos>=40 & freq_pos<=80;
plot(freq_pos(mZoom), mag_pos(mZoom), 'Color',[0.20 0.29 0.37], 'LineWidth',1); hold on;
xline(fc,'--','Color',[0.15 0.68 0.38],'LineWidth',1.2);
plot(freq_pos(idxMain), mainsAmp, 'o','MarkerSize',8, ...
     'MarkerFaceColor',[0.75 0.22 0.17],'MarkerEdgeColor','none');
xlabel('Frequency (Hz)'); ylabel('|X(f)| (mV)');
title('Zoom 40-80 Hz: isolated 60 Hz mains-hum peak'); grid on; box off;
legend('|X(f)|','Cut-off 40 Hz','60 Hz mains hum','Location','northeast'); legend boxoff;

%% Step 7-8 - Design FIR & IIR filters (calls the supplied FIR.m / IIR.m)
%  The two functions return digitalFilter objects produced by
%  designfilt('lowpassfir',...)  and  designfilt('lowpassiir',...).
Hd_fir = FIR();          % order 5, CutoffFrequency      = 40 Hz, fs = 360
Hd_iir = IIR();          % order 5, HalfPowerFrequency   = 40 Hz, fs = 360

% Magnitude responses
[H_fir, w_fir] = freqz(Hd_fir, 4096, fs);
[H_iir, w_iir] = freqz(Hd_iir, 4096, fs);

figure('Name','Step 8 - Filter responses','Color','w', ...
       'Position',[100 100 1000 380]);

subplot(1,2,1);
plot(w_fir, abs(H_fir), 'Color',[0.16 0.50 0.73], 'LineWidth',1.4); hold on;
plot(w_iir, abs(H_iir), 'Color',[0.75 0.22 0.17], 'LineWidth',1.4);
xline(fc, '--', 'Color',[0.15 0.68 0.38], 'LineWidth',1);
xlim([0 fs/2]); ylim([0 1.15]);
xlabel('Frequency (Hz)'); ylabel('|H(f)|  (linear)');
title('Magnitude response (linear)');
legend('FIR (order 5)','IIR (order 5)',sprintf('fc = %g Hz',fc), ...
       'Location','northeast'); legend boxoff; grid on; box off;

subplot(1,2,2);
plot(w_fir, 20*log10(abs(H_fir)), 'Color',[0.16 0.50 0.73], 'LineWidth',1.4); hold on;
plot(w_iir, 20*log10(abs(H_iir)), 'Color',[0.75 0.22 0.17], 'LineWidth',1.4);
xline(fc, '--', 'Color',[0.15 0.68 0.38], 'LineWidth',1);
yline(-3, ':', 'Color',[0.5 0.5 0.5]);
xlim([0 fs/2]); ylim([-60 5]);
xlabel('Frequency (Hz)'); ylabel('|H(f)|  (dB)');
title('Magnitude response (dB)');
legend('FIR (order 5)','IIR (order 5)',sprintf('fc = %g Hz',fc), ...
       'Location','southwest'); legend boxoff; grid on; box off;

% Print attenuation at 60 Hz so it can be quoted in the report
attFIR = 20*log10(abs(freqz(Hd_fir, [60], fs)));
attIIR = 20*log10(abs(freqz(Hd_iir, [60], fs)));
fprintf('\n--- Attenuation at 60 Hz ---\n');
fprintf('FIR : %6.2f dB\n', attFIR);
fprintf('IIR : %6.2f dB\n', attIIR);

%% Step 9: Apply the filters to noisySig (causal, like MATLAB's filter)
y_fir = filter(Hd_fir, noisySig);
y_iir = filter(Hd_iir, noisySig);

%% Step 10: Compare filtered signals with origSig
%  Plotting strategy
%  -----------------
%  - noisySig is shown as a thin, light tan line (#E6AE7E) in the
%    background of the top two panels.  This makes the *amount* of noise
%    the filters had to remove visible at a glance, without dominating
%    the plot.
%  - origSig is drawn slightly thicker than before (LineWidth 1.6) so it
%    can act as a clearly-visible "reference" behind the colored filter
%    output.  Where the filter matches origSig the colored line covers
%    the dark navy; where it differs (e.g. the IIR phase delay around
%    each R-peak), the dark navy peeks out and the difference becomes
%    obvious to the eye.
noisyClr = [0.902 0.682 0.494];        % #E6AE7E  -- soft amber/tan

figure('Name','Step 10 - Filtered vs original','Color','w', ...
       'Position',[100 100 950 720]);

subplot(3,1,1);
plot(t, noisySig, 'Color',noisyClr,         'LineWidth',0.5); hold on;  % faded background
plot(t, origSig,  'Color',[0.17 0.24 0.31], 'LineWidth',1.6);            % thick reference
plot(t, y_fir,    'Color',[0.16 0.50 0.73], 'LineWidth',1.0);            % FIR on top
ylabel('Voltage (mV)');
title('FIR output vs origSig');
legend('noisySig (input)','origSig','FIR-filtered noisySig', ...
       'Location','southwest'); legend boxoff;
xlim([0 T]); grid on; box off;

subplot(3,1,2);
plot(t, noisySig, 'Color',noisyClr,         'LineWidth',0.5); hold on;
plot(t, origSig,  'Color',[0.17 0.24 0.31], 'LineWidth',1.6);
plot(t, y_iir,    'Color',[0.75 0.22 0.17], 'LineWidth',1.0);
ylabel('Voltage (mV)');
title('IIR output vs origSig');
legend('noisySig (input)','origSig','IIR-filtered noisySig', ...
       'Location','southwest'); legend boxoff;
xlim([0 T]); grid on; box off;

subplot(3,1,3);
plot(t, y_fir, 'Color',[0.16 0.50 0.73], 'LineWidth',1.0); hold on;
plot(t, y_iir, 'Color',[0.75 0.22 0.17], 'LineWidth',1.0);
xlabel('Time (s)'); ylabel('Voltage (mV)');
title('FIR vs IIR -- direct comparison');
legend('FIR output','IIR output','Location','southwest'); legend boxoff;
xlim([0 T]); grid on; box off;

% Zoom on 2-4 s to expose the IIR phase delay (with noisySig as a faded
% reference so the reader can see exactly how much noise the filters had
% to deal with).  The legend is placed OUTSIDE the axes (above the plot)
% so it never overlaps any waveform.
figure('Name','Step 10 zoom','Color','w','Position',[100 100 950 400]);
plot(t, noisySig, 'Color',[0.85 0.55 0.20 0.35], 'LineWidth',0.6); hold on;  % faded amber
plot(t, origSig,  'Color',[0.12 0.18 0.27],      'LineWidth',1.8);           % dark reference
plot(t, y_fir,    'Color',[0.06 0.45 0.78],      'LineWidth',1.5);           % vivid blue
plot(t, y_iir,    'Color',[0.85 0.20 0.15],      'LineWidth',1.5);           % vivid red
xlim([2 4]);
ylim([-200 350]);                       % clip the rare noisySig spikes so the
                                        % filtered waveforms stay readable
xlabel('Time (s)'); ylabel('Voltage (mV)');
title('Zoom 2-4 s: phase delay introduced by the causal filters');
legend({'noisySig (input)','origSig','FIR output','IIR output'}, ...
       'Location','northoutside', 'Orientation','horizontal', 'Box','off');
grid on; box off;

% MSE comparison
mse_noisy = mean((noisySig - origSig).^2);
mse_fir   = mean((y_fir    - origSig).^2);
mse_iir   = mean((y_iir    - origSig).^2);
fprintf('\n--- MSE vs origSig (Step 9 outputs) ---\n');
fprintf('noisySig         : %10.2f\n', mse_noisy);
fprintf('FIR  causal      : %10.2f\n', mse_fir);
fprintf('IIR  causal      : %10.2f\n', mse_iir);

%% Step 11 - Improvements (do NOT change order or filter type)
%  (a) zero-phase filtering (filtfilt) -- same coefficients, applied
%      forward and reverse so the phase distortion cancels.
%  (b) a narrow 60 Hz IIR notch (Q = 30) cascaded after the low-pass
%      to remove the residual mains-hum line.

% (a) zero-phase versions of the SAME two designs
y_fir_zp = filtfilt(Hd_fir, noisySig);
y_iir_zp = filtfilt(Hd_iir, noisySig);

% (b) 60 Hz notch (second-order, Q=30) -- MATLAB Signal Processing Toolbox
[bN, aN] = iirnotch(fMains/(fs/2), (fMains/(fs/2))/30);   % wo, BW
y_iir_notch = filtfilt(bN, aN, y_iir_zp);
y_fir_notch = filtfilt(bN, aN, y_fir_zp);

% Combined frequency response for the report
[Hn,  wn]  = freqz(bN, aN, 4096, fs);
H_combined = H_iir .* Hn;

figure('Name','Step 11 - Improved response','Color','w', ...
       'Position',[100 100 950 360]);
plot(w_iir, 20*log10(abs(H_iir)), 'Color',[0.75 0.22 0.17], 'LineWidth',1.2); hold on;
plot(wn,    20*log10(abs(Hn)),    'Color',[0.55 0.27 0.67], 'LineWidth',1.2);
plot(w_iir, 20*log10(abs(H_combined)), 'Color',[0.09 0.63 0.52], 'LineWidth',1.6);
xline(fMains, ':', 'Color',[0.5 0.5 0.5]);
xlim([0 fs/2]); ylim([-80 5]);
xlabel('Frequency (Hz)'); ylabel('|H(f)|  (dB)');
title('Improvement: cascaded 60 Hz notch with the original IIR low-pass');
legend('IIR low-pass (order 5)','60 Hz notch (Q = 30)', ...
       'Combined: low-pass + notch','Location','southwest'); legend boxoff;
grid on; box off;

% Time-domain comparison of the improvements
figure('Name','Step 11 - Improvement time domain','Color','w', ...
       'Position',[100 100 950 800]);

subplot(3,1,1);
plot(t, origSig,  'Color',[0.17 0.24 0.31], 'LineWidth',0.8); hold on;
plot(t, y_iir,    'Color',[0.75 0.22 0.17], 'LineWidth',0.9);
plot(t, y_iir_zp, 'Color',[0.09 0.63 0.52], 'LineWidth',0.9);
ylabel('Voltage (mV)');
title('(a) Zero-phase filtering removes the phase delay');
legend('origSig','IIR (causal) -- step 9','IIR (zero-phase, filtfilt)', ...
       'Location','southwest'); legend boxoff;
xlim([0 T]); grid on; box off;

subplot(3,1,2);
plot(t, origSig,     'Color',[0.17 0.24 0.31], 'LineWidth',0.8); hold on;
plot(t, y_iir_zp,    'Color',[0.09 0.63 0.52], 'LineWidth',0.9);
plot(t, y_iir_notch, 'Color',[0.55 0.27 0.67], 'LineWidth',0.9);
ylabel('Voltage (mV)');
title('(b) Adding a 60 Hz notch removes the residual mains hum');
legend('origSig','IIR zero-phase only','IIR zero-phase + 60 Hz notch', ...
       'Location','southwest'); legend boxoff;
xlim([0 T]); grid on; box off;

subplot(3,1,3);
mZ = t>=0.45 & t<=0.85;
plot(t(mZ), origSig(mZ),     'Color',[0.17 0.24 0.31], 'LineWidth',1.6); hold on;
plot(t(mZ), y_iir(mZ),       'Color',[0.75 0.22 0.17], 'LineWidth',1.2);
plot(t(mZ), y_iir_notch(mZ), 'Color',[0.55 0.27 0.67], 'LineWidth',1.4);
xlabel('Time (s)'); ylabel('Voltage (mV)');
title('Zoom on a single PQRST complex (0.45-0.85 s)');
legend('origSig','Original IIR (causal)','Improved (filtfilt + notch)', ...
       'Location','northeast'); legend boxoff;
xlim([0.45 0.85]); grid on; box off;

% Spectrum after the improvement
X_imp   = fft(y_iir_notch);
mag_imp = abs(X_imp(half))*2/N;

figure('Name','Step 11 - Spectrum after improvement','Color','w', ...
       'Position',[100 100 950 360]);
plot(freq_pos, mag_pos, 'Color',[0.75 0.22 0.17], 'LineWidth',0.8); hold on;
plot(freq_pos, mag_imp, 'Color',[0.09 0.63 0.52], 'LineWidth',0.9);
xline(fMains,':','Color',[0.5 0.5 0.5]);
xline(fc,'--','Color',[0.15 0.68 0.38]);
xlim([0 fs/2]); xlabel('Frequency (Hz)'); ylabel('|X(f)| (mV)');
title('Spectrum before vs after the improved filter chain');
legend('noisySig','Improved output (IIR zero-phase + notch)', ...
       sprintf('60 Hz'), sprintf('fc = %g Hz',fc), ...
       'Location','northeast'); legend boxoff;
grid on; box off;

% Final MSE table
mse_fir_zp    = mean((y_fir_zp    - origSig).^2);
mse_iir_zp    = mean((y_iir_zp    - origSig).^2);
mse_iir_notch = mean((y_iir_notch - origSig).^2);
mse_fir_notch = mean((y_fir_notch - origSig).^2);

fprintf('\n--- MSE vs origSig (full table) ---\n');
fprintf('noisySig                       : %10.2f\n', mse_noisy);
fprintf('FIR  causal                    : %10.2f\n', mse_fir);
fprintf('IIR  causal                    : %10.2f\n', mse_iir);
fprintf('FIR  zero-phase (filtfilt)     : %10.2f\n', mse_fir_zp);
fprintf('IIR  zero-phase (filtfilt)     : %10.2f\n', mse_iir_zp);
fprintf('FIR  zero-phase + 60 Hz notch  : %10.2f\n', mse_fir_notch);
fprintf('IIR  zero-phase + 60 Hz notch  : %10.2f\n', mse_iir_notch);

fprintf('\nDone.\n');
