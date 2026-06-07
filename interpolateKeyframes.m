function maskZYX = interpolateKeyframes(maskZYX, keyframeSlices, opts)
% interpolateKeyframes Wypełnia brakujące przekroje (slices) między kluczowymi klatkami narysowanymi przez użytkownika.
%
% Dla każdej pary sąsiednich klatek kluczowych (a, b), brakujące przekroje
% pomiędzy nimi są rekonstruowane poprzez liniową interpolację
% transformaty odległości ze znakiem (SDF - signed distance transform) masek,
% z wyrównaniem środków ciężkości (centroid alignment) między A i B przed połączeniem.
%
% Zabezpieczenia przed przesunięciem (szczególnie ważne dla guzów/zmian):
%   - Jeśli dwie sąsiadujące klatki kluczowe są zbyt daleko od siebie w osi Z w stosunku do
%     `maxGap`, przerywamy połączenie, a przekroje pomiędzy nimi pozostają puste.
%     Zapobiega to tworzeniu "widmowych" guzów między dwiema niezwiązanymi zmianami.
%   - Jeśli środki ciężkości (w płaszczyźnie XY) A i B są zbyt daleko od siebie,
%     traktujemy je jako oddzielne zmiany i pomijamy interpolację między nimi.
%   - Wewnętrzny próg dla łączenia SDF rośnie ku środkowi (alpha=0.5),
%     nieznacznie kurcząc interpolowane maski, aby zredukować fałszywie dodatnie krawędzie.
%
% Dlaczego wyrównanie środków ciężkości ma znaczenie dla zmian (lesions):
%   Naiwne łączenie SDF zakłada, że kontury znajdują się w tej samej pozycji (X, Y).
%   Kontury wątroby są duże, więc to podejście jest wystarczające. Guzy są z kolei małe
%   i ich środek ciężkości może się przesuwać o kilka wokseli między przekrojami.
%   Bez wyrównania maska mogłaby ulec zniekształceniu lub całkowicie zniknąć.
%   Dzięki wyrównaniu: (a) przesuwamy A na środek ciężkości B, (b) łączymy SDF we wspólnym
%   układzie współrzędnych, (c) przesuwamy połączoną maskę na interpolowany środek ciężkości.
%
% Wejścia (Inputs):
%   maskZYX        : logiczna macierz [Z, Y, X] zawierająca narysowane maski na kluczowych przekrojach.
%   keyframeSlices : tablica 1xK z indeksami Z (przekrojami), na których rysował użytkownik.
%
% Wyjście (Output):
%   maskZYX ze wszystkimi przekrojami uzupełnionymi w zakresie [min(keys), max(keys)].

arguments
    maskZYX (:, :, :) logical
    keyframeSlices (1, :) double
    opts.target (1, 1) string = "liver" 
    % --- EKSTRAPOLACJA ("CZAPECZKI" NA KRAŃCACH) ---
    opts.extrapolate (1, 1) logical = true 
    opts.liverKeyframes (1, :) double = []
end

% Zatrzymujemy, jeśli mamy mniej niż 2 klatki (wymagane minimum do interpolacji)
if numel(keyframeSlices) < 2
    return;
end

% =========================================================================
% USTAWIENIA W ZALEŻNOŚCI OD RODZAJU TKANKI
% =========================================================================
if opts.target == "lesion"
    maxGap = 50;            % Pozwalamy na pominięcie do 50 pustych przekrojów
    maxDrift = 4.0;         % ZABEZPIECZENIE: Jeśli zmiana przesunęła się o >4 piksele na przekrój, to INNY guz
    shrinkMid = 0.0;        % Guzy są małe, NIE kurczymy ich w środku
    extrapShrink = 0.5;     
    doExtrapolate = false;  % CAŁKOWICIE WYŁĄCZAMY ekstrapolację dla guzów
else
    maxGap = 1000;          % Dla wątroby pozwalamy na dowolne przerwy
    maxDrift = 15.0;         
    shrinkMid = 1.0;        
    extrapShrink = 1.5;     
    doExtrapolate = false;  % Ekstrapolacja dla wątroby również jest wyłączona
end

% Sortowanie klatek kluczowych i pobranie całkowitej liczby przekrojów Z
keyframeSlices = sort(unique(keyframeSlices));
Z_total = size(maskZYX, 1);

% =========================================================================
% CZĘŚĆ 1: INTERPOLACJA (MIĘDZY KLATKAMI)
% =========================================================================
for k = 1:numel(keyframeSlices) - 1
    a = keyframeSlices(k);
    b = keyframeSlices(k + 1);
    
    % Jeśli przekroje są bezpośrednio obok siebie, nie ma czego interpolować
    if b - a < 2
        continue;
    end
    
    % --- TWARDA REGUŁA DLA GUZÓW ---
    % Jeśli pomiędzy przekrojami 'a' i 'b' narysowano wątrobę, ale bez guza, 
    % oznacza to, że mamy do czynienia z różnymi zmianami - przerywamy łączenie!
    if opts.target == "lesion" && ~isempty(opts.liverKeyframes)
        intermediateLiver = opts.liverKeyframes(opts.liverKeyframes > a & opts.liverKeyframes < b);
        if ~isempty(intermediateLiver)
            continue; 
        end
    end
    
    ma = squeeze(maskZYX(a, :, :));
    mb = squeeze(maskZYX(b, :, :));
    
    % Jeśli obie maski są całkowicie puste, przechodzimy dalej
    if ~any(ma, "all") && ~any(mb, "all")
        continue;
    end
    
    cA = centroidOf(ma);
    cB = centroidOf(mb);
    canAlign = ~isnan(cA(1)) && ~isnan(cB(1));
    
    % --- SPRAWDZENIE WIELU ZMIAN NA JEDNYM PRZEKROJU ---
    ccA = bwconncomp(ma);
    ccB = bwconncomp(mb);
    if ccA.NumObjects > 1 || ccB.NumObjects > 1
        canAlign = false; % Wyłączamy wyrównywanie środków, aby uniknąć błędów
    end
    
    % ZABEZPIECZENIE PRZED ZBYT DUŻYM PRZESUNIĘCIEM (DRIFT)
    if canAlign
        drift = norm(cB - cA);
        if drift > maxDrift * (b - a)
            continue; % Zbyt nagły skok - zrywamy połączenie!
        end
    end
    
    % Jeśli przerwa między klatkami przekracza dozwolony limit
    if (b - a) > maxGap
        continue;
    end
    
    % Wyrównanie masek do wspólnego środka ciężkości dla płynnego przejścia SDF
    if canAlign
        shiftAtoB = cB - cA;
        maAligned = shiftMask(ma, shiftAtoB);
        sdfA = signedDistance(maAligned);
        sdfB = signedDistance(mb);
    else
        sdfA = signedDistance(ma);
        sdfB = signedDistance(mb);
    end
    
    % Generowanie brakujących przekrojów
    for z = a + 1 : b - 1
        alpha = (z - a) / (b - a);
        sdfZ = (1 - alpha) * sdfA + alpha * sdfB;
        eps = shrinkMid * 2 * min(alpha, 1 - alpha);
        maskAtB = sdfZ >= eps;
        
        if canAlign
            cZ = (1 - alpha) * cA + alpha * cB;
            maskZ = shiftMask(maskAtB, cZ - cB);
        else
            maskZ = maskAtB;
        end
        maskZYX(z, :, :) = maskZ;
    end
end

% =========================================================================
% CZĘŚĆ 2: EKSTRAPOLACJA ("CZAPECZKI" W GÓRĘ I W DÓŁ)
% =========================================================================
if doExtrapolate
    % Dobudowywanie w GÓRĘ (przed pierwszą narysowaną klatką)
    firstKey = keyframeSlices(1);
    mFirst = squeeze(maskZYX(firstKey, :, :));
    if any(mFirst, "all") && firstKey > 1
        sdfFirst = signedDistance(mFirst);
        for z = firstKey - 1 : -1 : 1
            shrinkAmount = (firstKey - z) * extrapShrink;
            maskZ = sdfFirst >= shrinkAmount;
            
            if ~any(maskZ, "all")
                break; 
            end
            maskZYX(z, :, :) = maskZ;
        end
    end
    
    % Dobudowywanie w DÓŁ (za ostatnią narysowaną klatką)
    lastKey = keyframeSlices(end);
    mLast = squeeze(maskZYX(lastKey, :, :));
    if any(mLast, "all") && lastKey < Z_total
        sdfLast = signedDistance(mLast);
        for z = lastKey + 1 : Z_total
            shrinkAmount = (z - lastKey) * extrapShrink;
            maskZ = sdfLast >= shrinkAmount;
            
            if ~any(maskZ, "all")
                break; 
            end
            maskZYX(z, :, :) = maskZ;
        end
    end
end
end

% =========================================================================
% FUNKCJE POMOCNICZE
% =========================================================================

function c = centroidOf(maskBin)
% Oblicza środek ciężkości (centroid) binarnej maski
n = nnz(maskBin);
if n == 0
    c = [NaN, NaN];
    return;
end
[Y, X] = size(maskBin);
[yy, xx] = ndgrid(1:Y, 1:X);
c = [sum(yy(maskBin)) / n, sum(xx(maskBin)) / n];
end

function out = shiftMask(maskBin, shiftYX)
% Przesuwa maskę o zadaną liczbę pikseli w osiach Y i X
dy = round(shiftYX(1));
dx = round(shiftYX(2));
if dy == 0 && dx == 0
    out = maskBin;
    return;
end
out = imtranslate(maskBin, [dx, dy], "FillValues", 0);
end

function sdf = signedDistance(maskBin)
% Oblicza transformatę odległości ze znakiem (SDF) dla maski binarnej
sz = size(maskBin);
if ~any(maskBin, "all")
    sdf = -1e6 * ones(sz, "single");
    return;
end
if all(maskBin, "all")
    sdf = 1e6 * ones(sz, "single");
    return;
end
distOut = bwdist(maskBin);
distIn = bwdist(~maskBin);
sdf = single(distIn) - single(distOut);
end