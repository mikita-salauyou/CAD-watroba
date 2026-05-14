function d = dice(a, b)
% dice Sørensen–Dice coefficient between two binary masks.
%
%   d = dice(a, b) returns 0 if either mask is empty / all-false.
%   Both masks must have the same size.

arguments
    a logical
    b logical
end

if isempty(a) || isempty(b)
    d = 0;
    return;
end

if ~isequal(size(a), size(b))
    error("dice: masks have different sizes [%s] vs [%s].", ...
        num2str(size(a)), num2str(size(b)));
end

na = nnz(a);
nb = nnz(b);
if na == 0 && nb == 0
    d = 1;
    return;
end
if na == 0 || nb == 0
    d = 0;
    return;
end

inter = nnz(a & b);
d = 2 * inter / (na + nb);
end
